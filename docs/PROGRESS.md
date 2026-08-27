# Build progress

Status of the Accounic build against `context.md`. This is the file to read first when
picking the work back up.

**Last updated:** 2026-08-27 (tenth session)
**Current release:** [v1.5.0](https://github.com/VED2107/accounic/releases/latest)
**Overall:** Phases 1–4 complete and verified against the live database. Phase 5
(performance) measured and the client half tuned — see `docs/performance.md`. Phase 6
(hardening) partly done.

Both clients are finished and verified by looking at them, not only by testing them. The
web client is browser-verified at desktop and phone widths; the Flutter client renders
correctly on Windows and Android and is screen-verified. The credit/debit direction
semantics are correct across both (see `docs/accounting-direction.md`).

Everything found since v1.0.0 was found on a **phone**, and none of it was catchable by
`flutter analyze` or a passing test suite:

| Release | Fixed |
|---|---|
| 1.0.1 | auth errors that named the wrong cause |
| 1.0.2 | the missing INTERNET permission; Administration unusable at phone width |
| 1.0.3 | Delete hidden rather than explained; the person form going two-up on a phone |
| 1.0.4 | ~1,500 animation controllers per screen, most of them serving hover on a touch device |
| 1.0.5–1.0.7 | delete refusing a person whose history was all retracted; Save and Cancel sitting under the keyboard |
| 1.1.0 | multi-currency, opening balances, and the rest of the keyboard story on the person form |
| 1.1.1 | currency made genuinely per person: changing it no longer rewrites history |
| 1.5.0 | the displayed rate reconciles with the displayed conversion; a rate can be typed by hand and is frozen on the entry; one currency presenter across web and Flutter |
| 1.4.0 | entries keep the currency they were entered in; the anonymous execute surface closed; Android backups off |
| 1.3.0 | opening balance on the edit form; the dashboard shows every currency, not only the base one; the app tells you when a newer release exists |

Each now has a widget test pinning it — see README §4.

---

## 1. Phase status (`context.md` §34)

| Phase | Scope | Status |
|---|---|---|
| 1 — Foundation | repo, database, auth, profiles, RLS, admin role, env config | **Done, verified** |
| 2 — Core accounting | people, transactions, credit/debit, balances, settlements, history | **Done, verified** |
| 3 — Web | login, dashboard, people, person detail, add, settle, profile, admin | **Done, verified in browser** |
| 4 — Flutter | shared models, auth, screens, settle, desktop + Android adaptation | **Done, both binaries built** |
| 5 — Performance | indexes, query optimisation, caching, pagination, optimistic mutations | **Measured; client tuned in 1.0.4** — see `docs/performance.md` |
| 6 — Hardening | security audit, RLS tests, integrity tests, error handling, edge cases, prod config | **Mostly done** — see §7 |

---

## 2. Database — `db/` (complete)

Nine migrations, applied in order to the live Supabase project.

| File | Contents |
|---|---|
| `0001_foundation.sql` | extensions, enums, `profiles`, `app_admins`, `is_admin()` / `is_active_user()` / `current_owner()`, auth-user provisioning trigger |
| `0002_ledger.sql` | `people`, `transactions`, `settlements`, all CHECK constraints, composite-FK ownership, settlement validation trigger, over-settlement guards (both directions) |
| `0003_engine.sql` | **the accounting engine** — `person_balances`, `owner_summary`, `activity_feed` views; `transaction_settlement_status()` FIFO allocator; `dashboard()`; `search_all()` |
| `0004_mutations.sql` | every write RPC: person CRUD, transaction create/update/void, settlement create/void, `settle_account()`, `update_my_profile()`, `person_page()` |
| `0005_rls.sql` | grants, RLS enable + force, all policies, self-update guard, ledger key immutability |
| `0006_indexes.sql` | composite and trigram indexes for every access pattern |
| `0007_admin.sql` | `admin_list_users()`, `admin_set_user_active()`, `admin_system_info()`, `me()`, `grant_admin()` / `revoke_admin()` |
| `0008_activity.sql` | `activity_page()` paginated feed, `activity_summary()` buckets |
| `0009_delete_person_voided.sql` | `delete_person()` agreeing with the view about what "has transactions" means |
| `0010_currency.sql` | `currencies` reference table, `people.currency`, conversion provenance on every ledger row, `is_opening`, the per-owner `exchange_rates` cache, `convert_amount_minor()`, and the engine views rebuilt to carry currency |
| `0011_currency_mutations.sql` | the write path: currency and opening balance on `create_person()`, restatement on `update_person()` (withdrawn in 0013), conversion arguments on every money RPC, `set_person_opening_balance()` |
| `0012_currency_reads.sql` | `dashboard()`, `person_page()`, `search_all()`, `activity_page()` and `activity_summary()` made currency-aware |
| `0018_currency_presentation.sql` | `person_page()` timeline reads `activity_entries`, so every row carries the entered figure and its base equivalent; `exchange_rate_source` travels on every activity row; `rate_is_manual()`; an idempotent verification of the historical conversion data that rewrites no amount, currency or rate |
| `0017_entry_currency.sql` | `activity_entries` view; activity rows carry `entry_amount_minor`/`entry_currency` and `amount_base_minor`; `totals_by_currency` regrouped by ENTRY currency |
| `0016_revoke_anon.sql` | revokes EXECUTE from `anon` across `public` and resets the default privilege; `assert_own_workspace()` added to the three SECURITY DEFINER helpers that read tenant tables |
| `0015_dashboard_currencies.sql` | `dashboard()` gains `totals_by_currency` and `today_by_currency` — the same positions kept in their own currencies, never summed across them, only for currencies that carry entries. Additive: `summary` and `today` are byte-identical |
| `0013_person_currency.sql` | splits `people.currency` (the entry default) from `people.ledger_currency` (the frozen denomination); a currency change no longer rewrites history; `restate_person_currency()` dropped |

Supporting files: `db/seed.sql` (two isolated demo workspaces),
`db/tests/01_accounting_engine.sql`, `db/tests/02_rls_isolation.sql`,
`db/tools/{run-sql,smoke-api,bench}.mjs`.

---

## 3. Web — `web/` (complete, 52 source files)

Next.js 15.5 · React 19 · TypeScript strict (`noUncheckedIndexedAccess`) · Tailwind v4 ·
Supabase SSR. Production build: 9 routes, 103 kB shared JS.

**Routes:** `/login`, `/` (dashboard), `/people`, `/people/[id]`, `/activity`, `/profile`,
`/admin` — each with its own skeleton `loading.tsx`; plus `error.tsx`, `not-found.tsx` and
a person-scoped `not-found.tsx`.

**Server-side:** `lib/queries.ts` (one RPC per screen), `lib/actions.ts` (all user writes),
`lib/admin-actions.ts` (the only service-role caller), `lib/validation.ts` (zod),
`lib/errors.ts` (safe error translation), `lib/money.ts`, `lib/dates.ts`, `lib/types.ts`,
`lib/names.ts`, `lib/supabase/{server,client,admin,middleware}.ts`.

**Client components:** transaction sheet, settle sheet, person form, person picker,
amount input, quick search (⌘K), app shell, modal + confirm dialog, UI primitives.

---

## 4. Flutter — `app/` (complete, 25 source files + 2 test files)

Flutter 3.29 · Riverpod · go_router · supabase_flutter. Android APK and Windows `.exe`
both build against the live backend.

- `core/` — `config.dart` (dart-define), `money.dart` (mirror of `money.ts`), `dates.dart`,
  `theme.dart` (Material 3 + `MoneyColors` extension), `failure.dart`
- `data/` — `models.dart` (mirror of `types.ts`), `ledger_repository.dart`,
  `auth_repository.dart`; the only Supabase callers in the app
- `providers.dart` — Riverpod wiring, debounced search, one `invalidateLedger` helper
- `ui/` — router, adaptive shell (rail ≥900px / bottom bar below), 7 screens, 4 sheets,
  shared widgets

---

## 5. Verification evidence

All run against the user's live Supabase project, not mocks.

| Check | Result |
|---|---|
| `node db/tools/run-sql.mjs test` | 8 suites pass, including 34 currency-reconciliation assertions (`db/tests/08`) |
| `node db/tools/smoke-api.mjs` | 33/33 pass over real HTTP with the anon key |
| `cd web && npx tsc --noEmit` | clean |
| `cd web && npm test` | 84 pass |
| `cd web && npx next build` | succeeds, 9 routes |
| `cd app && flutter analyze` | no issues |
| `cd app && flutter test` | 200 pass |
| `flutter build windows --release` | `accounic.exe` built |
| `flutter build apk --release` | `app-release.apk` built, 24.3 MB |
| Installer | silent-installed and the installed binary launched |
| Browser walkthrough | login → dashboard → person → settle ₹5,000; ₹17,000 → ₹12,000, FIFO chip ₹6,500 → ₹1,500 left |

**Bugs found and fixed during that walkthrough** (neither was caught by typecheck, build or
unit tests):

1. Sign out did nothing — `void signOut()` in a transition swallowed the `redirect()`
   throw. Fixed as a form action.
2. Dashboard crashed with any data — `initials()` was exported from a `'use client'`
   module and called during a server render. Moved to `lib/names.ts`.

---

## 6. Performance — measured, client tuned

The full write-up, including what made the Flutter client janky on Android and the
before/after counts, is in [`docs/performance.md`](./performance.md). The database
numbers below are unchanged.

`node db/tools/bench.mjs 30`, server time (planning + execution) on the seeded workspace:

| Query | median | p95 |
|---|---|---|
| `dashboard()` — whole screen, one call | 9.8 ms | 15.6 ms |
| `activity_page()` | 7.6 ms | 11.9 ms |
| `person_page()` | 5.2 ms | 8.1 ms |
| `owner_summary` | 3.2 ms | 3.6 ms |
| `person_balances` full list | 3.3 ms | 5.0 ms |
| `search_all()` | 1.6 ms | 3.4 ms |

Fast enough that no tuning is warranted at this data volume. **Not yet done:** re-measuring
at realistic scale (10k+ transactions), where the `person_balances` lateral joins and the
`transaction_settlement_status()` FIFO loop are the two things most likely to bend first.

---

## 7. What is left

### 7.1 Branding

- [x] Web: Accounic name and mark throughout — metadata, sidebar, mobile header, login
- [x] Web: Poppins for the wordmark and headings, Inter for UI text, both via `next/font`
- [x] Web: accent moved off indigo to the brand blue; full token set in `globals.css`
- [x] Flutter: app title, `pubspec.yaml` name (`accounic`), mark drawn in
      `ui/widgets/brand.dart`, Accounic palette in `core/theme.dart`
- [x] Flutter: `assets/brand/` registered; Poppins bundled in `assets/fonts/`
- [x] Android label in `AndroidManifest.xml`; Windows product name in `Runner.rc`
- [x] Windows binary builds as `accounic.exe`
- [x] README and remaining prose: Ledger → Accounic

### 7.2 Documentation

- [x] `docs/performance.md` — measured numbers, and what made the Flutter client slow
- [x] `docs/deployment.md` — migrations, Vercel, both binaries, and how a release is cut
- [x] `docs/security.md`
- [x] `README.md`

### 7.3 Production readiness

- [x] `cd web && npm run build` — clean; 103 kB shared first-load JS, largest route 190 kB
- [x] Delete the demo seed users (`demo@example.com`, `friend@example.com`) — done
      2026-08-26, before the repository was made public: `db/tools/smoke-api.mjs` carries
      their password in plain text, and `demo@example.com` was an admin. Both logins were
      re-checked afterwards and are refused. See `docs/deployment.md` §2
- [ ] Decide on rate limiting (currently none at the application layer)
- [ ] Release APK is **debug-signed**, not unsigned — `android/app/build.gradle.kts` points
      its release build at `signingConfigs.getByName("debug")`. Fine for sideloading, wrong
      for the Play Store. Needs a keystore and a gitignored `key.properties`, and losing
      that keystore permanently blocks updates to installed copies.

### 7.4 Repository

- [x] Pushed to **https://github.com/VED2107/accounic** — **public** since 2026-08-26, so
      the in-app update check can read the Releases API without a token. `main` is current.
      `web/.env.local` is gitignored and was verified absent from the tree before the
      first push.

### 7.5 Deliberately deferred

Offline sync (`context.md` §22 — the repository layer is structured for it), notifications
(§31), and anything in the "not built" list in the README.

---

## 8. Deliverables checklist (`context.md`)

| # | Deliverable | State |
|---|---|---|
| 1 | Final architecture | done — README §1 |
| 2 | Database schema | done — `db/migrations/0001`–`0002` |
| 3 | SQL migrations | done — 8 files |
| 4 | RLS policies | done — `0005_rls.sql` |
| 5 | Authentication | done |
| 6 | Admin implementation | done |
| 7 | Accounting/balance engine | done — `0003_engine.sql` |
| 8 | Settlement logic | done |
| 9 | Next.js web app | done |
| 10 | Flutter Android app | done |
| 11 | Flutter Windows app | done |
| 12 | Shared API/data contracts | done — `types.ts` + `models.dart` |
| 13 | Tests | done — 82 SQL, 33 API, 23 web, 65 Dart |
| 14 | Seed/demo data | done |
| 15 | Env config example | done — `web/.env.local.example` |
| 16 | Deployment instructions | done — `docs/deployment.md` |
| 17 | Performance notes | done — `docs/performance.md` |
| 18 | Security notes | done — `docs/security.md` |


---

## 9. UI/UX pass — second session

### 9.1 Direction semantics (both clients) — **done and correct**

The words *credit* and *debit* were attached to the wrong directions. The rule now, stated
once in `docs/accounting-direction.md` and implemented once per client:

| Movement | Called | Balance | Colour |
|---|---|---|---|
| person → owner | Credit | payable | red |
| owner → person | Debit | receivable | green |

Only the vocabulary was wrong. The engine's balances, settlement pairings and colours
already matched this rule, because the stored enum labels are the reverse of the spoken
words. **No migration**: flipping the engine would invert the meaning of every row already
recorded. The mapping lives in `web/src/lib/direction.ts` and `app/lib/core/direction.dart`
and nowhere else; four Dart tests pin it, including the deliberate inversion.

### 9.2 Web — done and verified in a browser

- **Design system.** Dark-first token set in `globals.css` (surfaces, ink, brand ramp,
  money colours, radius, elevation, motion). Light scheme kept and tuned. Theme is
  user-selectable — system / light / dark — via `lib/theme.ts` with a no-FOUC boot script.
- **Primitives.** Button, field, card, panel, avatar, badge, segmented control, skeleton,
  empty state, toast, modal/bottom sheet, page header.
- **Screens.** Dashboard (two sides + net hero, sparklines, insights, quick actions),
  People (totals strip, search, direction filter, sort, archived), Person detail (hero
  balance, settle/credit/debit, four figures, history/details/notes tabs), Activity
  (30-day totals, day grouping, filter), Profile (identity, details, appearance, security,
  session), Admin (stats, user rows, destructive actions marked out), Login.
- **Motion.** CSS entrances and stagger (no JS); GSAP loaded dynamically for the one thing
  that earns it — a balance that travels to its new value when a settlement lands.
- **Avatars** are coloured per person from a hash of the name (`lib/avatar-color.ts`), so
  red and green mean money and nothing else.
- **Verified in a browser** at 2133px and 555px: every screen, a real partial settlement
  (₹750 then ₹250 against Priya Nair), the success state, the balance animation, and both
  reversals. Demo data was restored — the two test settlements remain as voided history.
- **Two real bugs found and fixed by that walkthrough**, both invisible to typecheck:
  1. `useActionState` keeps its result for the life of the component, so success effects
     re-fired on unrelated state changes — a repeating "Transaction recorded" toast, and a
     settle sheet that replayed its success screen on reopen. Now keyed on result identity.
  2. The settle sheet reported the wrong remaining figure, because the server action's own
     revalidation had already moved the balance by the time the effect read it. It now
     snapshots the figures at submit.

### 9.3 Flutter — third session: rebuilt, verified on screen, released

The blank body was fixed at the end of the second session (a stretch `Row` in a scroll view
— `docs/decisions.md` §20). This session was the quality pass, and unlike the last one it was
**verified by looking at it**: the Windows binary was driven route by route and screenshotted,
and every figure on screen was reconciled against `person_balances` and `owner_summary` in
the live database.

**Design system.** `core/layout.dart` (breakpoints, spacing, radii, one content measure),
`core/icons.dart` (Lucide, addressed by meaning), `ui/widgets/app_page.dart` (one page
chrome), `ui/widgets/forms.dart` (`AppTextField`, `AppDropdown`, `SaveButton`,
`SettingsGroup`, `SettingsRow`), `Hoverable` and `Haptics` in `ui/motion.dart`, `Segmented`
in `ui/widgets/common.dart`. Decisions §22–§25.

**Screens.** Dashboard rebuilt around one position card (net headline, two paired sides, a
30-day trend line) rather than three equal cards; People given a real toolbar, hover states
and semantic totals; Activity given an animated segmented filter and day groups; Person
detail restyled and moved *inside* the shell so the rail survives a drill-down; Profile
rebuilt as a settings page with grouped sections, a two-column desktop layout and a save bar
that only exists while something is unsaved; Administration given a responsive stats row,
hover rows and contextual menus.

**Splash.** `ui/splash/` — the mark assembling itself over 1900ms, on one controller and one
painter, never awaiting anything. Decision §26. The Android launch drawable and the Windows
window brush were both painting white before Flutter's first frame; both now match the
splash ground.

**Bugs found by looking, not by testing.** Cancel did nothing on any sheet whose route result
was not a bool (§24, now pinned by `test/sheet_cancel_test.dart`); the split bar was drawn at
4px between two dark tones and was invisible; centred columns of differing widths made the
whole layout slide sideways on every route change (§22).

**Verified:** `flutter analyze` clean, 40 Dart tests pass, Windows release and installer
built, dashboard/people/person/activity/profile/admin walked and screenshotted, all figures
reconciled against the database.

### 9.3.1 Second session — the state this replaced

Applied: Accounic theme and tokens, Poppins, drawn brand mark, motion primitives
(`ui/motion.dart`), bottom bar with a docked primary action, rebuilt dashboard, people
directory with totals and a direction filter, person hero with settle/credit/debit, the
activity summary strip and day grouping, quarter-step amount entry, and a settlement
success state.

**This was resolved in v1.0.0 and is kept only as the record of how it was found.** The
cause was a stretch `Row` inside a scroll view failing layout silently — not the animation
primitives suspected below. The reasoning that led there is in `docs/decisions.md` §22–§26,
and `test/dashboard_screen_test.dart` now pins it.

At the time: `flutter analyze` was clean and all 32 tests passed, but the app did not
render:

> **On Windows, the app launches, signs in and draws the rail, the brand and the sidebar
> correctly — and the entire dashboard content area is blank.** No cards, no skeleton, no
> empty state, no error note. The app bar renders ("Dashboard"), so the Scaffold is fine
> and the body is not painting.

The suspects considered at the time, in order — **all three were wrong**, which is the
useful part of this record:

1. `Reveal` / `Stagger` in `ui/motion.dart` — they wrap children in `flutter_animate`
   `.fadeIn()`. If the animation never runs, `both`-style fill leaves the child at opacity
   zero and everything inside disappears. **Test first by returning `child` unchanged from
   both widgets** and re-running; if the content comes back, the fault is there.
2. The `dashboardProvider` sitting in `loading` forever, with `_DashboardSkeleton` also
   invisible for reason (1) — the skeleton is built from the same primitives.
3. The account in use (`vedchauhan2107@gmail.com`) has no people and no transactions, so
   the correct render is the *empty state* — which is also wrapped in `Reveal`.

Reproduce:

```
cd app
flutter run -d windows \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
```

Run it **attached** (not the detached `.exe`) so the console shows exceptions — the
detached binary was how this was first seen, and it swallowed whatever was thrown.

Also outstanding on Flutter at the time — **all closed by the v1.0.0 rebuild**, which put
every screen on one design system (`core/layout.dart`, `core/icons.dart`,
`ui/widgets/app_page.dart`, `ui/widgets/forms.dart`):

- [x] Profile screen still had the pre-Accounic layout
- [x] Person timeline rows not restyled to match the web's
- [x] Search sheet only partly restyled
- [x] Phone-width layouts verified — by widget tests at real phone metrics, and by the
      1.0.2–1.0.4 fixes that came out of using the APK on a device

Still true: **no Android emulator runs on this machine.** The Pixel_8 AVD hangs on a black
screen with the default GPU and needs `-gpu swiftshader_indirect -no-snapshot-load`.
Android verification is therefore widget tests at phone metrics plus sideloading the APK —
never an automated run on a device.

### 9.4 Also done this session

- `vedchauhan2107@gmail.com` was granted admin (a row in `public.app_admins`).

---

## 10. Fifth session — multi-currency, opening balances, and the keyboard (v1.1.0)

### 10.1 What shipped

| Area | What changed |
|---|---|
| Database | three additive migrations (`0010`–`0012`). No table dropped, no row rewritten, no id regenerated |
| Currency | a currency per person, defaulting to the workspace's; `shared/currencies.json` is the single definition, generated into SQL, TypeScript and Dart |
| Conversion | entered amount, currency, rate, timestamp and source stored on every converted row; the database does the arithmetic, the clients preview it |
| Opening balances | a flagged transaction, so the existing engine computes it correctly by construction; replacing one retracts the old rather than editing it |
| Rates | open.er-api.com with Frankfurter behind it, cached per owner in `exchange_rates`, refreshed at most every 12 hours, never blocking a save |
| Android | the person form rebuilt around the keyboard: pinned actions, live inset padding, drag- and tap-to-dismiss, chained focus, 48dp targets |
| Web / Windows / Android | the same data model and the same RPCs; nothing platform-specific in the accounting path |

### 10.2 Verification evidence

All against the user's live Supabase project.

| Check | Result |
|---|---|
| `node db/tools/snapshot.mjs before` / `after` / `diff` | every count, every person id and every net balance unchanged across the migration |
| `node db/tools/run-sql.mjs test` | 128 assertions pass (82 existing + 46 new currency assertions) |
| `node db/tools/smoke-currency.mjs` | 23/23 over real HTTP as an ordinary signed-in user |
| `cd web && npx tsc --noEmit` | clean |
| `cd web && npm test` | 44 pass (23 money + 21 currency) |
| `cd web && npx next build` | succeeds, 9 routes |
| `cd app && flutter analyze` | no issues |
| `cd app && flutter test` | 100 pass |
| `flutter build windows --release` | `accounic.exe` built |
| `flutter build apk --release` | `app-release.apk` built, 24.5 MB |
| Windows binary | launched and screenshot: signs in, renders the activity feed against the new RPCs |
| Rate sources | both reachable and returning; `open.er-api.com` publishes 166 currencies including AED, Frankfurter 29 and not AED |

### 10.3 Two things worth keeping

**The engine did not change.** `amount_minor` still means "minor units, in this account's
currency" — which is what it meant when there was one currency — so every balance computed
before the migration computes identically after it. `snapshot.mjs` exists to prove that
rather than assert it, and it is the check to run before any future migration.

**Currency change restates, and says so first.** The database refuses the first attempt and
explains what will happen; that refusal *is* the confirmation step, and nothing has been
written when the user sees it. See `docs/decisions.md` §35 for why the "only affects future
transactions" option is not available under this data model.

### 10.4 Known limitations

- **Writes still need the network.** Rates are cached and degrade gracefully; transactions
  are not queued offline, because every balance is computed by the database and there is no
  local write queue. Unchanged from v1.0 (`context.md` §22).
- **The release APK is still debug-signed** — see `docs/deployment.md` §5.
- **`db/tools/smoke-api.mjs` cannot finish** on this database: it signs in as
  `friend@example.com` from `db/seed.sql`, which is not present in the live project. Its
  first ~30 checks pass; the cross-tenant half needs `run-sql.mjs seed` first, which would
  add demo rows to a production database. Not run for that reason.
- **No Android emulator on this machine.** Android verification remains widget tests at real
  phone metrics plus sideloading the APK.


---

## 11. Sixth session — currency made genuinely per person (v1.1.1)

v1.1.0 shipped per-person currency and got one thing wrong, in the one place it mattered
most: changing a person's currency **restated** their account, rewriting `amount_minor` on
every historical row at a confirmed rate. The brief had asked for the opposite — a currency
change must affect future transactions only, and a ₹1,000 entry must still read ₹1,000
afterwards.

**The cause was a conflation, not a constraint.** `people.currency` was answering two
different questions with one column: *what is a new entry for this person typed in* and
*what is this person's stored `amount_minor` denominated in*. Those agree until somebody
changes currency, and then one of them has to give. v1.1.0 let the denomination give.

**The fix splits them.** `people.currency` keeps the first job; a new nullable column,
`people.ledger_currency`, takes the second and is frozen the first time the two diverge.
NULL means "never diverged", so the column is NULL on every pre-existing row and the
resolution chain collapses to exactly what 0010 did:

    entry  = people.currency        ?? profiles.currency
    ledger = people.ledger_currency ?? people.currency ?? profiles.currency

Full reasoning in `docs/decisions.md` §38; §35 is marked superseded rather than deleted.

**The engine did not change.** `amount_minor` still means "minor units, in this person's
ledger currency". `person_balances` did not gain a row per currency, `settle_account()` and
the over-settlement guards are untouched, and no screen that reads a net balance changed.
The migration reads no ledger row and writes none — `db/tools/snapshot.mjs before | after |
diff` came back clean on all eight fingerprints, every person id and every net balance.

What each client had to learn is that a person has **two** currencies and which one answers
which question:

* the amount field defaults to the person's entry currency,
* every displayed figure is labelled with their ledger currency,
* and the two are shown side by side only when they differ, because a person who has never
  switched has one currency and should be told about exactly one.

Also in this release:

* `restate_person_currency()` is **dropped**, not left unused — a granted RPC that rewrites
  every amount on an account is the behaviour being removed. Dropping it retires the
  transaction-local `accounic.restating` marker too, restoring 0005's rule that a voided row
  cannot be edited by anyone.
* A settlement entered in the new currency is converted into the ledger currency *before*
  the over-settlement guard compares it with the outstanding figure. Comparing dollars with
  dirhams there would let an account be over-settled.
* `update_person()` still accepts `p_restate_rate_e9` and ignores it, so a v1.1.0 client
  keeps working. The smoke test pins a v1.0.7-style call as well.

**Verified:** 172 SQL assertions, 26 HTTP checks on a throwaway account, 51 web tests, 112
Flutter tests, both binaries built, and the data-safety snapshot clean against the live
database (4 users, 4 profiles, 16 people, 27 transactions, 16 settlements — unchanged).

---

## 12. Seventh session — the actual converted amount (v1.1.2)

Automatic conversion is right about the market and sometimes wrong about the money. Ahmed's
account is in dirhams, ₹1,000 is handed over, the rate says AED 44.20 — and the counter gives
AED 43. Both figures are facts. This release records both, and lets the ledger take the one
that actually changed hands.

### 12.1 What shipped

| Area | What changed |
|---|---|
| Database | one additive migration (`0014`). Two columns, one helper, five widened RPCs. **No historical row written** |
| Model | `conversion_mode` (`automatic` \| `manual`) and `auto_converted_amount_minor`; NULL mode reads as automatic, so pre-1.1.2 rows need no backfill |
| Ledger | `amount_minor` takes the manual figure when there is one — the balance is money that moved, not money quoted |
| Audit | the entered amount, its currency, the rate, its timestamp and its source all survive an override untouched; the rate figure is kept beside it |
| Edit | an edit that says nothing about currency preserves the override; switching back to automatic recomputes from the row's own rate |
| Settlement | the over-settlement guard compares the **actual** amount with what is outstanding |
| Opening balance | takes an override too, both on `create_person()` and on `set_person_opening_balance()` |
| Web / Windows / Android | one panel per client: the automatic figure by default, `Use actual amount` beside it, and the automatic estimate kept on screen once overridden |
| Android | the shell's bottom bar and docked `+` no longer sit on top of an open form — every modal is pushed on the root navigator |

Full reasoning in `docs/decisions.md` §39 (the ledger records what changed hands) and §40
(a form is not part of the shell it was opened from).

### 12.2 Verification evidence

All against the user's live Supabase project.

| Check | Result |
|---|---|
| `node db/tools/snapshot.mjs before` / `after` / `diff` | clean — 21 people, 37 transactions, 17 settlements, every id and every net balance unchanged |
| `node db/tools/run-sql.mjs test` | 210 assertions pass (172 existing + 38 new) |
| `node db/tools/smoke-currency.mjs` | 34/34 over real HTTP as an ordinary signed-in user |
| `cd web && npx tsc --noEmit` | clean |
| `cd web && npm test` | 64 pass (51 existing + 13 conversion) |
| `cd web && npx next build` | succeeds, 9 routes, 103 kB shared |
| `cd app && flutter analyze` | no issues |
| `cd app && flutter test` | 119 pass (112 existing + 7 new) |

### 12.3 The two things worth keeping

**The migration writes nothing.** `conversion_mode` NULL means automatic — which every row
written before this release was — so there is no backfill, no historical amount touched and
no id regenerated. `activity_feed` resolves the NULL, so no client has to know the column
was ever added. This is the same device `people.ledger_currency` uses in `0013`.

**The footer bug was structural.** `ShellRoute` builds the shell around its own nested
navigator, and `showModalBottomSheet` defaults to the nearest one — so every sheet opened
*inside* the shell's Scaffold, underneath its `bottomNavigationBar` and its docked `+`.
One argument, `useRootNavigator: true`, fixes it in the three places that open a modal.
Hiding the bar behind a flag would have been a second source of truth for "is a form open",
and it would have drifted the first time a sheet was dismissed by a gesture.

---

## 13. Eighth session — the premium UI pass, first slice (v1.1.3)

A visual-polish brief arrived covering typography, colour, the sidebar, the dashboard,
every list row, forms, loading, empty and error states, density and accessibility across
all three clients. This release is the **first slice**: the parts that are token-level, so
that everything downstream of them improves at once rather than screen by screen.

### 13.0 A regression in v1.1.2, found by opening the app

The dashboard failed to render at all: **`TypeError: Cannot read properties of undefined
(reading 'currency')`**, shown to the user as the generic error boundary with a digest.

`0014` rewrote `dashboard()`, `person_page()` and `activity_page()` in order to add two
columns to their select lists. The first cut of `dashboard()` was transcribed from `0013`
starting at the wrong line and **silently lost its `profile` key** — which every dashboard
render reads on its second line — along with the empty-workspace `summary` fallback.

Nothing caught it. The migration applied cleanly, 172 SQL assertions passed, the data
snapshot was clean, `tsc` was clean, the production build succeeded, and the screen was
blank. It was found the way every serious defect in this project has been found: by
opening the thing and looking at it.

`db/tests/06_manual_conversion.sql` now asserts the **key set** of all four page RPCs,
which is the actual contract between the database and every client. A read RPC that
silently stops returning a key is otherwise invisible until a screen goes white.

**If you applied `0014` from the v1.1.2 tag, re-apply the corrected file** — the RPC is
replaced in place, nothing else changes, and no row is touched.

### 13.1 What shipped

| Area | What changed |
|---|---|
| Contrast | `ink-muted` and `ink-faint` lifted until both clear 4.5:1 in both schemes; `ink-subtle` added underneath for genuinely decorative text. `ink-faint` was 4.03:1 — under the AA floor for the 12px metadata it carries |
| Money typography | four sizes and nothing between them, in both clients: hero / large / row / small. All tabular, all negatively tracked |
| Labels | `.stat-label` and `.stat-note` (web), `context.statLabel` / `context.statNote` (Flutter) — the name above a figure and the line under it |
| Dashboard | net position promoted to a full-measure hero card; receivable, payable and **settled** below it as the working behind it. The web dashboard's three-up row is gone |
| Rows | activity rows split into kind / when / note instead of one grey run-on string; a person row states its own currency, and a balance carries its ≈ base-currency equivalent |
| State | the direction under a balance is a bordered tinted pill containing the word — never colour alone |
| Sidebar | selected reads as *you are here* (tint + hairline + brand rule) rather than as a filled button; the primary action sized as a control at 44px |

Reasoning in `docs/decisions.md` §41 (dimness is not a style) and §42 (a financial figure
is not body text).

### 13.2 Verification evidence

| Check | Result |
|---|---|
| `cd app && flutter analyze` | no issues |
| `cd app && flutter test` | 133 pass (119 + 14 new token tests) |
| `node db/tools/run-sql.mjs test` | 216 assertions (210 + 6 key-set assertions) |
| `node db/tools/smoke-currency.mjs` | 34/34 |
| Browser | dashboard reproduced broken, fixed, and re-rendered against live data |
| `app/test/design_tokens_test.dart` | computes WCAG luminance for both schemes; fails under 4.5:1 |
| `cd web && npx tsc --noEmit` | clean |
| `cd web && npm test` | 64 pass |
| `cd web && npx next build` | succeeds, 9 routes, 103 kB shared |
| Windows binary | rebuilt, launched and screenshotted against live data |

### 13.3 What is deliberately still open

The brief is larger than one release. Not yet done, and worth doing next in this order:

1. **Forms** — grouping the person and transaction sheets into labelled sections
   (identity / currency / opening balance / contact) rather than one flat column.
2. **Loading and empty states** — skeletons that match the final layout on every screen,
   and empty states that carry the action that fixes them.
3. **Error states** — naming the thing that failed and offering the retry, rather than
   "something went wrong".
4. **Profile and Administration** — the two screens with the most unused space.
5. **The dashboard chart** — hover readout, axis labels, and a real empty state.

None of them are blocked; they were left because a token pass first means each of them is
smaller than it would have been.
