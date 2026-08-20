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
