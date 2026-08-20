# Build progress

Status of the Accounic build against `context.md`. This is the file to read first when
picking the work back up.

**Last updated:** 2026-08-20 (second session)
**Overall:** Phases 1–4 complete and verified against the live database. Phase 5
(performance) measured but not tuned. Phase 6 (hardening) partly done.

Since the first session: the Accounic branding and a full design system are wired into the
**web** client, which is verified in a browser at desktop and phone widths. The
credit/debit direction semantics were corrected across both clients (see
`docs/accounting-direction.md`). The **Flutter** client has had the same treatment applied
to its code but **does not render correctly yet** — see §9.

---

## 1. Phase status (`context.md` §34)

| Phase | Scope | Status |
|---|---|---|
| 1 — Foundation | repo, database, auth, profiles, RLS, admin role, env config | **Done, verified** |
| 2 — Core accounting | people, transactions, credit/debit, balances, settlements, history | **Done, verified** |
| 3 — Web | login, dashboard, people, person detail, add, settle, profile, admin | **Done, verified in browser** |
| 4 — Flutter | shared models, auth, screens, settle, desktop + Android adaptation | **Done, both binaries built** |
| 5 — Performance | indexes, query optimisation, caching, pagination, optimistic mutations | **Measured, not tuned** — see §6 |
| 6 — Hardening | security audit, RLS tests, integrity tests, error handling, edge cases, prod config | **Mostly done** — see §7 |

---

## 2. Database — `db/` (complete)

Eight migrations, applied in order to the live Supabase project.

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
| `cd app && flutter test` | 28 pass |
| `flutter build windows --release` | `ledger.exe` built |
| `flutter build apk --debug` | `app-debug.apk` built |
| Browser walkthrough | login → dashboard → person → settle ₹5,000; ₹17,000 → ₹12,000, FIFO chip ₹6,500 → ₹1,500 left |

**Bugs found and fixed during that walkthrough** (neither was caught by typecheck, build or
unit tests):

1. Sign out did nothing — `void signOut()` in a transition swallowed the `redirect()`
   throw. Fixed as a form action.
2. Dashboard crashed with any data — `initials()` was exported from a `'use client'`
   module and called during a server render. Moved to `lib/names.ts`.

---

## 6. Performance — measured, not tuned

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
- [ ] Android label in `AndroidManifest.xml`; Windows product name in `Runner.rc`
- [ ] Rename the Windows binary — still builds as `ledger.exe`
      (`app/windows/runner/CMakeLists.txt` → `BINARY_NAME`)
- [ ] README and remaining prose: Ledger → Accounic

### 7.2 Documentation

- [ ] `docs/performance.md` — README links it; the numbers in §6 above go here
- [ ] `docs/deployment.md` — README links it; Vercel + Supabase, APK signing, Windows packaging
- [x] `docs/security.md`
- [x] `README.md`

### 7.3 Production readiness

- [x] `cd web && npm run build` — clean; 103 kB shared first-load JS, largest route 190 kB
- [ ] Delete the demo seed users (`demo@example.com`, `friend@example.com`) before real use
- [ ] Decide on rate limiting (currently none at the application layer)
- [ ] Accept the Android licences (`flutter doctor --android-licenses`) for release APK signing
- [ ] Release APK is unsigned — needs a keystore for distribution

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
| 13 | Tests | done — 72 SQL, 33 API, 23 web, 28 Dart |
| 14 | Seed/demo data | done |
| 15 | Env config example | done — `web/.env.local.example` |
| 16 | Deployment instructions | **outstanding** |
| 17 | Performance notes | measured; **write-up outstanding** |
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

### 9.3 Flutter — code written, **not working yet**

Applied: Accounic theme and tokens, Poppins, drawn brand mark, motion primitives
(`ui/motion.dart`), bottom bar with a docked primary action, rebuilt dashboard, people
directory with totals and a direction filter, person hero with settle/credit/debit, the
activity summary strip and day grouping, quarter-step amount entry, and a settlement
success state.

`flutter analyze` is clean and all 32 tests pass, but the app does not render:

> **On Windows, the app launches, signs in and draws the rail, the brand and the sidebar
> correctly — and the entire dashboard content area is blank.** No cards, no skeleton, no
> empty state, no error note. The app bar renders ("Dashboard"), so the Scaffold is fine
> and the body is not painting.

Not yet diagnosed. The likely suspects, in order:

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

Also outstanding on Flutter:

- [ ] Profile screen still has the pre-Accounic layout
- [ ] Person timeline rows not restyled to match the web's
- [ ] Search sheet only partly restyled
- [ ] Android emulator: the Pixel_8 AVD hangs on a black screen with the default GPU;
      it boots with `-gpu swiftshader_indirect -no-snapshot-load`. The app was never
      confirmed running on Android — only on Windows.
- [ ] No screenshots taken on a phone-width layout yet

### 9.4 Also done this session

- `vedchauhan2107@gmail.com` was granted admin (a row in `public.app_admins`).
