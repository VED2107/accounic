# Build progress

Status of the Accounic build against `context.md`. This is the file to read first when
picking the work back up.

**Last updated:** 2026-08-21 (fourth session)
**Current release:** [v1.0.4](https://github.com/VED2107/accounic/releases/latest)
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
| `node db/tools/run-sql.mjs test` | 34 accounting + 38 RLS assertions pass |
| `node db/tools/smoke-api.mjs` | 33/33 pass over real HTTP with the anon key |
| `cd web && npx tsc --noEmit` | clean |
| `cd web && npm test` | 23 pass |
| `cd web && npx next build` | succeeds, 9 routes |
| `cd app && flutter analyze` | no issues |
| `cd app && flutter test` | 61 pass |
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
- [ ] Delete the demo seed users (`demo@example.com`, `friend@example.com`) before real use
- [ ] Decide on rate limiting (currently none at the application layer)
- [ ] Release APK is **debug-signed**, not unsigned — `android/app/build.gradle.kts` points
      its release build at `signingConfigs.getByName("debug")`. Fine for sideloading, wrong
      for the Play Store. Needs a keystore and a gitignored `key.properties`, and losing
      that keystore permanently blocks updates to installed copies.

### 7.4 Repository

- [x] Pushed to **https://github.com/VED2107/accounic** (private). `main` is current.
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
