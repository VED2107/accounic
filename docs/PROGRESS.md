# Build progress

Status of the Accounic build against `context.md`. This is the file to read first when
picking the work back up.

**Last updated:** 2026-08-20
**Overall:** Phases 1–4 complete and verified against the live database. Phase 5
(performance) measured but not tuned. Phase 6 (hardening) partly done. Branding assets
created but **not yet wired into either client**.

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

### 7.1 Branding — the live task

Assets exist in `brand/` (six SVG variants + `build-assets.mjs`, already rasterised into
both clients' icon slots). **Neither client uses them yet.** Remaining:

- [ ] Web: replace "Ledger" in `app/layout.tsx` metadata, `app-shell.tsx` sidebar and mobile
      header, and `login/page.tsx` — swap `WalletIcon` for the Accounic mark
- [ ] Web: load Poppins (`next/font/google`) and use it for the wordmark and headings
- [ ] Web: move the accent from indigo `#4338CA` to the brand blue in `globals.css`
      (keep green/rose reserved for receivable/payable — see `docs/decisions.md`)
- [ ] Flutter: app title in `main.dart`, `pubspec.yaml` name/description, the wallet glyph in
      `shell.dart` and `login_screen.dart`
- [ ] Flutter: register `assets/brand/` in `pubspec.yaml`; add `flutter_svg` or use the PNG
- [ ] Flutter: accent colour in `theme.dart` to match the web
- [ ] Android label in `AndroidManifest.xml`; Windows product name in `Runner.rc`
- [ ] Rename the Flutter binary from `ledger.exe` (`pubspec.yaml` → `name:`)
- [ ] README, docs and package names: Ledger → Accounic

### 7.2 Documentation

- [ ] `docs/performance.md` — README links it; the numbers in §6 above go here
- [ ] `docs/deployment.md` — README links it; Vercel + Supabase, APK signing, Windows packaging
- [x] `docs/security.md`
- [x] `README.md`

### 7.3 Production readiness

- [ ] Re-run `cd web && npm run build` — the app was edited after the last production build
- [ ] Delete the demo seed users (`demo@example.com`, `friend@example.com`) before real use
- [ ] Decide on rate limiting (currently none at the application layer)
- [ ] Accept the Android licences (`flutter doctor --android-licenses`) for release APK signing
- [ ] Release APK is unsigned — needs a keystore for distribution

### 7.4 Deliberately deferred

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
