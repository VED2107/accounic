# Design decisions

The choices in this build that were not obvious, and why they went the way they did.
Written down because the code shows *what* was done, not what was rejected.

---

## 1. Settlements carry a direction, not a sign

A settlement has `direction` (`in` / `out`) and a positive `amount_minor`, rather than a
signed amount.

`in` reduces outstanding receivable; `out` reduces outstanding payable. The alternative —
negative amounts on the transactions table — collapses two different events (a debt being
created, a debt being paid) into one row type, which makes "what is still outstanding"
require interpreting signs, and makes a partial payment indistinguishable from a credit
note.

`transaction_id` on a settlement is an **optional reference**, not a foreign-key-driven
allocation. Balances never depend on it. It means "the user pressed Settle on this row",
and it only biases display allocation.

## 2. Balances aggregate; per-row status is FIFO

Two different questions, answered two different ways:

- **What is outstanding?** Pure aggregation: `Σ credit − Σ settled-in`. Deterministic,
  index-friendly, and exactly what `context.md` §33's test cases specify.
- **Is *this invoice* settled?** `transaction_settlement_status()` allocates settlements
  across transactions: a settlement naming a transaction is applied there first, and any
  remainder spills onto the oldest still-open transaction of the same direction.

Keeping these separate matters. Making balances depend on allocation would mean every
dashboard number ran a loop; making per-row status a simple aggregate would mean the
timeline could not honestly say "₹6,500 left" on a specific invoice.

The targeted-before-FIFO rule exists for a concrete case: pressing Settle on a newer
invoice while an older one is open must credit the invoice the user clicked, not the
oldest one.

## 3. Money is bigint everywhere, and the views cast back

Amounts are integer minor units. The subtlety: `sum()` over `bigint` returns `numeric` in
PostgreSQL, and numeric reaches a client as a **decimal string**. That would reintroduce
exactly the floating-point-shaped hazard §7 forbids, one layer further out.

Every money expression in `0003_engine.sql` is therefore cast back to `bigint`. There is a
test asserting the dashboard's receivable arrives as a JSON *number*, and the Dart models
coerce defensively in case a future schema change reintroduces numeric.

## 4. Ownership is structural, not just policy

A child row proves it shares an owner through a **composite foreign key**
`(owner_id, person_id) → people(owner_id, id)`, not through a trigger or an RLS predicate
alone.

This holds even for service-role writes and bulk imports, where RLS is bypassed. RLS
protects the API; the composite FK protects the data.

## 5. `current_owner()` returns NULL rather than raising

Every RLS predicate is `owner_id = public.current_owner()`. For an anonymous or deactivated
caller that function returns `NULL`, so the predicate is `NULL` — never true.

The failure mode is "see nothing". Had it raised, a caller could distinguish "deactivated"
from "no rows", and any policy that forgot to handle the exception would fail open.

## 6. Admin membership lives in a table with no write policy

`app_admins` is separate from `profiles` specifically so that no column a user can update
determines their privilege. There is no insert/update/delete policy on it at all, so
`authenticated` cannot write to it by any route through PostgREST.

Admins deliberately get **no** read access to other users' ledgers. Administration is user
management; it is not a key to the books.

## 7. Deletion is not exposed

The API grants no `DELETE` on `transactions` or `settlements`. Void is the only path, and
voided rows stay visible in the timeline. Deleting a *person* is allowed only while they
have no transactions.

This is what makes "historical settlement relationships must not become corrupted"
(§17) enforceable rather than aspirational.

## 8. Over-settlement guards are deferred constraint triggers

They fire at end of statement, not per row, so a multi-row statement is judged on its final
state. Consequence worth remembering: the SQL test suites must issue
`set constraints all immediate`, because they roll back and never reach commit.

The same invariant is checked from the transaction side too — voiding or shrinking a
transaction can strand settlements above the basis just as easily as an oversized
settlement can.

## 9. One RPC per screen

`dashboard()` and `person_page()` return their whole payload as JSON in a single call
rather than the client issuing five queries. This is what makes the "no N+1, no huge
payloads" requirement (§23) structural instead of a discipline.

Corollary: `activity_page()` exists because `activity_feed` is a `UNION` view, and
PostgREST cannot embed a relationship through a view — it has no foreign-key metadata. The
join to `people` therefore has to happen server-side.

## 10. Colour carries exactly one meaning

Green means money coming in; rose means money going out. Nothing else in the UI is allowed
to use those hues decoratively, because the whole point of §8 is that direction should be
legible without reading a word.

This is why the Accounic brand gradient (blue → teal → green) stays confined to the logo,
and the UI accent takes the blue end rather than the green. A green "Save" button would
quietly compete with "you will receive".

## 11. Validation is three layers, and the database is the guarantee

Browser, then zod on the server, then CHECK constraints and RPC-level exceptions. A request
that bypasses the UI still meets the last two. Amounts are re-parsed server-side from raw
text — the client is never the authority on a number.

## 12. Money formatting is duplicated on purpose

`web/src/lib/money.ts` and `app/lib/core/money.dart` are deliberate mirrors, with mirrored
test suites asserting the same cases. Sharing them would mean a codegen step or a shared
package for ~150 lines; the tests are the cheaper guarantee. If the two ever disagree, a
user sees two different balances on two devices — so the tests, not the code, are the
contract.

## 13. Layout breakpoints are width-based, never platform-based

The Flutter shell switches between a navigation rail and a bottom bar at 900px of width,
not on `Platform.isWindows`. A Windows window dragged narrow behaves like a phone; an
Android tablet in landscape gets the rail. One rule, no per-platform branches.

## 14. The dark scheme is the product; light is a courtesy

Accounic leads with near-black surfaces and one brand blue. The light scheme is kept and
tuned to the same rules — not mechanically inverted — because a ledger gets read for long
stretches in whatever light the reader is in.

The choice is the user's: system, light or dark, stored per device. On the web that is
`data-theme` on `<html>` with a boot script inlined in `<head>`, because without it the
page paints dark and swaps on every navigation for anyone who picked light. Flutter uses
`ThemeMode.system`.

The alternative — forcing dark — looks decisive in a screenshot and is hostile at a desk
by a window.

## 15. Colour has three jobs and no fourth

Brand blue means *interaction*. Green means *money coming in*. Red means *money going out*.
Everything else is a neutral surface or ink at some strength.

Two consequences follow, and both were changes:

- The blue → cyan → teal → green brand gradient is confined to the mark, one hairline at
  the top of a hero panel, the primary action's tonal fill, and the active nav marker. It is
  never a field of colour behind content, because a gradient behind a number changes what
  the number's colour appears to be.
- **Avatars are coloured by identity, not by balance.** They used to be tinted green or red
  from the person's net position, which made a directory of ten people a wall of the two
  colours that are supposed to mean money. Now each person gets a stable colour hashed from
  their name, out of a palette that deliberately excludes the receivable green and payable
  red (`web/src/lib/avatar-color.ts`, `app/lib/core/avatar_color.dart` — same hues, same
  FNV-1a hash, so the same person is the same colour on both clients).

## 16. Credit and debit are a vocabulary layer, not an arithmetic one

The full statement is in `docs/accounting-direction.md`. The decision recorded here is
*where the fix went*.

The database's `transactions.type` enum labels are the reverse of what the words mean to a
user: stored `'credit'` is the owner → person direction, which is the receivable one. Every
balance, settlement pairing and colour derived from those columns was already correct; only
the two words were on the wrong ends.

So the correction is a presentation-layer vocabulary map — one module per client, and
nothing outside it may compare a stored type against a literal to label or colour anything.
There is **no migration**, and that is the point: flipping the engine would invert the
meaning of every row already recorded, turning a ₹5,000 receivable entered last month into a
₹5,000 payable. That is data corruption wearing the costume of a fix.

The cost is that a reader of the SQL must remember the inversion. It is paid once, in the
header comment of each direction module and in the doc, and pinned by four Dart tests that
assert the inversion on purpose — so that anyone "fixing" those tests has to read the doc
first.

## 17. Entrances are CSS; only one thing gets a JavaScript tween

On the web, every entrance and list stagger is a CSS class with an inline `animation-delay`.
An entrance is a one-shot, non-interactive animation, so it needs no runtime, no hydration
and no client component — two hundred ledger rows can stagger without shipping a byte of
animation code.

GSAP is loaded, dynamically and in its own chunk, for exactly one thing: a balance that
travels to its new value when it changes. That is an interruptible tween over a formatted
value which must retarget mid-flight if a second settlement lands, and it is the one place
motion carries information rather than polish — it shows the user the consequence of what
they just did, on the number they were looking at. It deliberately does **not** animate on
first paint; a balance counting up from zero on every page load is decoration.

Flutter mirrors the same motion language with the same three bands (micro 100–180ms,
component 180–300ms, major 300–450ms) and the same easing family, implemented natively in
`app/lib/ui/motion.dart`. Nothing is shared between the two but the numbers.

## 18. Sparklines are drawn by hand, from data already fetched

The dashboard's trend lines are one SVG path on the web and one `CustomPainter` in Flutter.
No charting library on either side: it is a single smoothed path with no axes, grid or
tooltip, and the figure beside it carries the value.

Every point comes from the same thirty-day `activity_summary` the activity screen already
uses — no extra query and no invented data. Where a number cannot be derived honestly the
graphic is not drawn, which is why the series helpers can all return null. The "up 12.5%"
chip compares the recent half of the window against the earlier half and says exactly that,
because that is the only honest comparison a flow series supports.

## 19. Poppins is bundled; the body face is the platform's

Both clients use Poppins for the brand and headings, matching the wordmark.

The web pairs it with Inter, self-hosted by `next/font`. Flutter bundles Poppins as an asset
but leaves body text to the platform face — Roboto on Android, Segoe UI on Windows. Shipping
a second megabyte of font to a phone to fill a role the system already fills well is a poor
trade, and `google_fonts` at runtime would mean a network request for text.

## 20. A layout-phase failure is invisible; a build-phase one is loud

The Flutter dashboard rendered an entirely blank body — no cards, no skeleton, no empty
state, no error note — while `flutter analyze` and all 32 tests passed. The cause was one
line: the two side cards sat in a `Row` with `CrossAxisAlignment.stretch` inside a vertical
scroll view.

Stretch hands each child the parent's cross-axis extent. Inside a scroll view that extent is
infinity, so `BoxConstraints forces an infinite height` was thrown from `performLayout`.

That distinction is the lesson worth keeping. An exception thrown while **building** a widget
is replaced by Flutter's red `ErrorWidget`, which is impossible to miss. An exception thrown
while **laying out** a render object leaves that subtree without a size, and an unsized
subtree is silently skipped at paint time. The screen looks empty and nothing announces the
fault — which is why every static check stayed green and why the fault survived a session.

Three things changed as a result:

1. The Row is wrapped in `IntrinsicHeight`, which is how the app's four other stretch Rows
   were already written. Equal-height cards, finite constraints.
2. `Failure` now carries its `cause` and stack trace; `ErrorNote.forError` prints the safe
   sentence for the user and the cause underneath it in debug builds only; every repository
   catch passes its stack through; and `main()` installs `FlutterError.onError` and
   `PlatformDispatcher.onError`, so a detached binary can no longer swallow what it throws.
3. `app/test/dashboard_screen_test.dart` pumps the real screen at desktop and phone widths
   across loading, data, empty and error, and fails on any framework exception. Reverting the
   `IntrinsicHeight` makes it fail with the original message, so the test genuinely covers
   the bug rather than the fix.

Unit tests over models could never have caught this. Only pumping the widget could.

## 21. Flutter's admin screen is deliberately smaller than the web's

The web `/admin` can create a user and reset a password. Both call Supabase's admin API,
which requires the **service-role key** — a credential that bypasses RLS entirely. That key
is safe in a server-rendered route, where it never leaves the machine, and unsafe in anything
installed on a laptop or a phone, where anyone can read it out of the binary.

So the Flutter admin screen carries only what the four `SECURITY DEFINER` RPCs allow with
the anon key: the account directory (`admin_list_users`), enable/disable
(`admin_set_user_active`), grant/revoke administrator (`grant_admin` / `revoke_admin`) and
the system counters (`admin_system_info`). Each of those re-checks `is_admin()` server-side,
so forcing the screen open buys nothing. Creating an account and resetting a password stay on
the web, and the screen says so rather than hiding a missing feature.

This is parity of *authority*, not parity of *buttons*: the Flutter app can do everything an
administrator can safely do from a client binary, and nothing that would require shipping a
key that defeats the security model.

## 22. One page chrome, one content measure

Every screen used to build its own `Scaffold`, its own app bar and its own centred column,
and the widths had drifted: the profile capped its content at 620px, the dashboard and the
admin screen at 1000px, everything else at 760px. Because those columns were *centred*,
moving between two pages slid the whole layout sideways. Two screens also carried an app-bar
title **and** an in-body headline, which read as two competing page titles.

`ui/widgets/app_page.dart` now owns all of it. One title per page, placed by width — a short
app bar on a phone, an editorial header inside the page on a desktop — one gutter scale, and
one content measure (`ContentWidth.standard`, 1040px) used by every screen.

Centring and a single measure depend on each other. Left-aligning instead was tried and
rejected: with the rail on the left it looked deliberate on the dashboard and lopsided on
every page whose content was narrower. Centred plus identical widths is the only combination
where changing route moves nothing but the content.

Where a page genuinely needs a shorter measure than the column — a form, whose fields must
not stretch to a thousand pixels — it takes it *inside* the column. `SettingsGroup` puts its
heading and explanation in a 232px column beside the card on a desktop width, which is why
the profile fills the screen without a single field growing.

## 23. Lucide, addressed by meaning

The app mixed Material glyphs from three different families — `dashboard_outlined`,
`timeline`, `swap_horiz_rounded`, `inventory_2_outlined`, `person_search_outlined` — at four
optical sizes. `core/icons.dart` replaces the lot with Lucide at one stroke weight, and
screens name the *role* (`AppIcons.receivable`) rather than the picture, so a glyph judged
wrong is changed in one place.

Lucide has one weight rather than an outline/filled pair, so a selected navigation
destination is marked by a tinted plate behind its glyph instead of by swapping the glyph.
That is the more honest signal anyway: a filled icon says "a different thing", a tinted one
says "you are here".

Direction glyphs — ↗ receivable, ↙ payable, ↔ settlement — follow
`docs/accounting-direction.md` and never appear without the word and the colour beside them.
An arrow is an accelerator for a reader who already knows the rule, not a statement of it.

## 24. Cancel pops nothing, never `false`

`SheetScaffold` is shared chrome, and its Cancel button called `Navigator.pop(false)`. That
is fine on a `Route<bool>` and a **runtime type error** on any other — and the person sheet's
route is a `Route<Person>`. The error was swallowed by the gesture handler, so the symptom
was not a crash but a Cancel button that silently did nothing, on exactly the sheets whose
result was not a bool.

Cancel now pops nothing at all. Every caller already reads a null result as "the user backed
out", so null is both type-safe on every route and the correct answer on every one of them.
`app/test/sheet_cancel_test.dart` pins it at both presentations.

The same pass moved the person, transaction and settle sheets onto `showAppSheet`, which
picks the presentation from the width: a bottom sheet on a phone, a centred panel on a
desktop. A bottom sheet on a 2000px monitor strands the content at the bottom of the screen,
a long way from where the user was looking.

## 25. Person detail belongs inside the shell

It was a sibling of the shell, pushed above it, so drilling into an account removed the
navigation rail. On a desktop that left a column of content and half a screen of nothing
beside it, and it took the user's navigation away at the exact moment they were most likely
to want it. The web client keeps its sidebar on `/people/[id]`; the Flutter client now does
too.

It is still a *push* rather than a sibling tab, so Android's back gesture and Alt+Left return
to the list. Tab destinations cross-fade (`fadeThrough`) because they have no order; the
drill-down slides in from the trailing edge (`drillIn`) because it genuinely is below the
list it came from.

## 26. The splash is a fixed length of time, not a loading screen

`ui/splash/` draws the Accounic mark assembling itself: the ribbon "A" drawn along its own
arc length, three bars rising 70ms apart, the growth arrow travelling its path with the head
arriving last, a 150ms settle, then the wordmark. The geometry is `brand/accounic-icon.svg`
coordinate for coordinate; the only thing added is time.

Three decisions worth keeping:

1. **One controller.** The whole sequence is intervals into a single 1900ms
   `AnimationController` (`splash_timeline.dart`). Six controllers would mean six tickers,
   six chances to drift apart on a loaded frame, and no single place to read the timing off.
2. **One painter.** The mark is one `CustomPainter` inside a `RepaintBoundary`, not a widget
   per element. Stacked `Transform`s and `ClipRect`s would each force layout and a
   `saveLayer` every frame; this draws the whole mark in a handful of path operations with
   no layout at all.
3. **It never awaits anything.** Not the network, not Supabase, not a session refresh.
   Accounic must open offline, so the splash runs for a fixed time and the router comes up
   *behind* it — `SplashGate` is an overlay on `MaterialApp.builder`, not a route. The moment
   a splash starts awaiting a future it has stopped being a brand moment and become a loading
   screen that lies about being one. `SplashTimeline.failsafe` lifts it after five seconds
   even if the ticker never completes.

The Android launch drawable was **white**, in both the light and the dark resource sets,
which produced a white flash on every cold start of a dark app; the Windows window class had
a null background brush, with the same result. Both now paint `#070A12` — the exact colour
`SplashBackground` grounds itself with, so the handover from the native launch surface to
Flutter's first frame is invisible. Those three values must change together.

## 27. Auth errors are safe to relay; collapsing them was not

Every `AuthException` in the Flutter client became one sentence — "That email and password
combination is not correct." — and on the web every auth error carried no SQLSTATE, so it
fell straight through `friendlyMessage` to whatever fallback the caller passed. Both were
written for the sign-in form and then applied to every auth call in the product.

The cost showed up on password change. This project's GoTrue rejects exactly two things for
`updateUser({password})`, verified against the live API:

```
422 same_password  New password should be different from the old password.
422 weak_password  Password should be at least 6 characters.
```

Both clients enforce ten characters with mixed case and a digit before sending, so
`weak_password` is unreachable and **`same_password` is the only rejection a real user can
hit**. They were told "Your password could not be changed." on web and "That email and
password combination is not correct." on Flutter. Both are true and neither can be acted on;
the one fact that would have fixed it in seconds — you have typed the password you already
have — was the one fact being discarded.

So auth codes are now mapped in `app/lib/core/failure.dart` and `web/src/lib/errors.ts`,
which are kept in step. The reasoning for relaying them is that an auth error describes the
credential the user has *just typed*, not anything about another account, so there is nothing
to leak — unlike a database error, which can carry table and constraint names.

`invalid_credentials` is the deliberate exception and stays vague. Distinguishing "no such
user" from "wrong password" turns the sign-in form into a way to enumerate which email
addresses have accounts.

Unrecognised codes still fall back rather than inventing a reason, and the raw GoTrue text
stays on `Failure.detail` for debug builds. `app/test/auth_errors_test.dart` pins all of it,
including the deliberate vagueness.

## 28. The release APK had no INTERNET permission

Accounic worked on Windows and on every Android debug build, and the release APK could not
reach Supabase at all. The sign-in screen said *"That email and password combination is not
correct."*

`android/app/src/main/AndroidManifest.xml` never declared
`android.permission.INTERNET`. Flutter's stock `src/debug/` and `src/profile/` manifests do
declare it — with a comment saying it is there so the tool can hot-reload — and those are
merged into debug and profile builds only. So the permission was present in every build
anyone develops against and absent from the one that ships.

It is close to undetectable from the desk: `flutter analyze` is clean, every unit and widget
test passes, the debug APK installs and works, and the release APK builds without a warning.

The second half of the bug is why it lied about the reason. Supabase surfaces a failed
request as `AuthRetryableFetchException`, which **extends `AuthException`** — so it matched
the auth branch in `Failure.from`, found no matching GoTrue code, and fell through to the
caller's fallback. The sign-in call's fallback is the credentials sentence, so a request that
never left the device was reported as a wrong password.

Both halves are fixed and both are pinned:

- `test/android_manifest_test.dart` reads the main manifest and fails if the permission is
  missing. A test that asserts on a build-config file rather than on code is unusual, and
  earns its place here because nothing else in the suite can see the difference between a
  debug build and a release one.
- `test/auth_errors_test.dart` asserts that a fetch failure is reported as a connection
  problem and never as bad credentials.

The general rule the fallback broke: **never let a transport failure inherit a
domain-specific error message.** A request that did not arrive tells you nothing about what
was in it.
