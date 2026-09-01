# Accounic

A small, fast, personal accounting system. Three clients, one backend, one database.

Current release: **[v1.9.0](https://github.com/VED2107/accounic/releases/latest)** —
Windows installer, Windows portable zip, and an Android APK. The app checks GitHub
Releases on launch and tells you when a newer one exists.

Every push runs three workflows — web (typecheck · tests · production build), Flutter
(analyze · tests · debug APK) and SQL (every migration and every suite against a
throwaway Postgres). A green CI means all three passed.

Answers four questions and little else (`context.md` §35):

1. Who do I have an account with?
2. How much do they owe me?
3. How much do I owe them?
4. What has been settled and what remains?

| Client | Stack | Location |
|---|---|---|
| Web | Next.js 15 · React 19 · TypeScript strict · Tailwind v4 | `web/` |
| Android | Flutter 3.29 · Riverpod · go_router | `app/` |
| Windows desktop | the same Flutter codebase | `app/` |
| Backend | PostgreSQL / Supabase — schema, RLS, accounting engine | `db/` |

Design source of truth: [`context.md`](./context.md). Visual map: [`mindmap.md`](./mindmap.md).

---

## 1. Architecture

```
                  ┌──────────────────────────────┐
                  │       PostgreSQL / Supabase  │
                  │                              │
                  │  profiles · people           │
                  │  transactions · settlements  │
                  │                              │
                  │  RLS  ── tenant isolation    │
                  │  views ─ balance engine      │
                  │  RPCs ── validated writes    │
                  └──────────────┬───────────────┘
                                 │  anon key + user JWT
              ┌──────────────────┼──────────────────┐
              │                  │                  │
        Next.js web        Flutter Android    Flutter Windows
       (+ service-role
        for admin only)
```

**The rule that shapes everything:** the database computes every balance. No client
adds up a column. `web/src/lib/money.ts` and `app/lib/core/money.dart` format money
and parse input — they never derive a balance.

### Where each concern lives

| Concern | Home | Notes |
|---|---|---|
| Balance arithmetic | `db/migrations/0003_engine.sql` | `person_balances`, `owner_summary` views |
| Per-transaction settled/open | `transaction_settlement_status()` | FIFO with targeted-settlement priority |
| Validated writes | `db/migrations/0004_mutations.sql` | every client writes through these RPCs |
| Tenant isolation | `db/migrations/0005_rls.sql` + `0016_revoke_anon.sql` | RLS forced on every table; `anon` holds no EXECUTE in `public` |
| Currency of record | `db/migrations/0017_entry_currency.sql` | entries keep the currency they were entered in; base is supplementary |
| Live exchange rates | `web/src/lib/rates.ts`, `app/lib/data/rates_repository.dart` | open.er-api.com, falling back to frankfurter.dev (ECB). Free, keyless, cached per owner |
| Update check | `app/lib/data/update_repository.dart` | GitHub Releases API + semver; links are host-allow-listed |
| Admin operations | `db/migrations/0007_admin.sql` + `web/src/lib/admin-actions.ts` | service-role never leaves the server |
| Money representation | `money.ts` / `money.dart` | integer minor units, mirrored line for line |
| Currency definitions | `shared/currencies.json` | one source; `db/tools/sync-currencies.mjs` generates the SQL seed, the TS and the Dart |
| Currency conversion | `db/migrations/0010_currency.sql` | `convert_amount_minor()`; clients preview, the database decides |
| Exchange rates | `web/src/lib/rates.ts` · `app/lib/data/rates_repository.dart` | open.er-api.com, Frankfurter behind it, cached per owner |

---

## 2. The accounting model

Amounts are **integer minor units**. `₹100.50` is stored as `10050`. How many minor
units make a major one is a property of the currency, not a constant: the yen has none
(`¥1,000` is `1000`) and the Kuwaiti dinar has three. No float, anywhere, ever, in the
money path.

Each person has their own **account currency**, defaulting to the workspace's. Every row
of theirs is denominated in it; an amount entered in another currency is converted at the
door and the row keeps what was actually handed over — the original amount, its currency,
the rate, when it was taken and where it came from. A later rate move never touches a
recorded transaction (`docs/decisions.md` §34–§37).

```
total_credit           = Σ credit transactions       (not void)
total_debit            = Σ debit transactions        (not void)
settled_in             = Σ settlements direction in  (not void)
settled_out            = Σ settlements direction out (not void)

outstanding_receivable = total_credit - settled_in
outstanding_payable    = total_debit  - settled_out
net_balance            = outstanding_receivable - outstanding_payable
```

`net_balance > 0` → they owe you. `< 0` → you owe them. `0` → settled.

**Credit** = they owe you. **Debit** = you owe them. A settlement records money that
actually moved and reduces the outstanding side; it never edits or deletes the
original transaction, so history stays intact (`context.md` §9, §17).

Workspace totals sum the *per-person net* rather than raw columns, so someone you
both owe and are owed by is counted once, on the side they actually land.

---

## 3. Getting started

### Prerequisites

- Node 20+ (built on 24)
- Flutter 3.29+ with the Android SDK and, for desktop, Visual Studio Build Tools
- A Supabase project (or any PostgreSQL 15+ with the Supabase auth schema)

### 3.1 Database

Apply the migrations in order — they are numbered and must run in sequence:

```bash
cd db/tools && npm install && cd ../..
node db/tools/run-sql.mjs migrate       # 0001 … 0012
node db/tools/run-sql.mjs seed          # optional demo data
node db/tools/run-sql.mjs test          # 12 suites, 328 assertions, rolled back
```

The runner reads `DATABASE_URL` from the environment or from `web/.env.local`.
Without it, paste each file into the Supabase SQL editor in filename order.

Then promote your first administrator (service role / SQL editor only):

```sql
select public.grant_admin('you@example.com');
```

### 3.2 Web

```bash
cd web
cp .env.local.example .env.local     # fill in the three values
npm install
npm run dev                          # http://localhost:3000
```

### 3.3 Flutter — Android and Windows

Configuration is passed at build time; nothing is committed:

```bash
cd app
flutter pub get

flutter run -d windows \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key

flutter run -d android \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Release builds:

```bash
flutter build windows --release --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
flutter build apk     --release --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…
```

A build without those defines starts and tells you so, rather than failing later
with a network error.

---

## 4. Tests

| Suite | Command | Covers |
|---|---|---|
| Accounting engine | `node db/tools/run-sql.mjs test` | §33 arithmetic, FIFO allocation, integrity guards |
| Currency engine | (same command) | per-person currency, opening balances, conversion, historical rates |
| Per-person currency | (same command) | four people on four currencies, NULL fallback, a currency change that rewrites nothing |
| Currency over HTTP | `node db/tools/smoke-currency.mjs` | the whole feature as a signed-in user, on a throwaway account it deletes |
| Data safety | `node db/tools/snapshot.mjs before` · `… after` · `… diff` | counts, ids and every person's net balance, before and after a migration |
| RLS / authorisation | (same command) | cross-tenant reads and writes, privilege escalation, disabled accounts, anon |
| End-to-end API | `node db/tools/smoke-api.mjs` | the real anon-key path: sign-in, RPCs, isolation |
| Web units | `cd web && npm test` | money parsing, formatting, balance meaning |
| Flutter units | `cd app && flutter test` | the same money cases, model/contract parsing, and the UI regressions below |
| Types | `cd web && npm run typecheck` · `cd app && flutter analyze` | strict TS, zero analyzer issues |

The money suites in `web` and `app` deliberately assert the *same* cases. If they
ever disagree, a user is seeing two different balances on two devices.

The Flutter suite also pins the failures that a green analyzer cannot see. Every one
of these shipped at least once, and none of them was catchable without rendering the
widget at a real size:

| Suite | Catches |
|---|---|
| `android_manifest_test.dart` | the INTERNET permission going missing from the release build |
| `auth_errors_test.dart` | a transport failure being reported as bad credentials |
| `admin_reachable_test.dart` | Administration failing at phone width, and non-admins not being refused |
| `dashboard_screen_test.dart` | the dashboard body failing layout and rendering blank |
| `sheet_cancel_test.dart` | Cancel doing nothing on a sheet whose route is not `Route<bool>` |
| `person_actions_test.dart` | Delete vanishing from the menu, and the person form going two-up on a phone |
| `motion_cost_test.dart` | a controller per list row coming back — see [`docs/performance.md`](./docs/performance.md) |
| `person_form_keyboard_test.dart` | the person form becoming unusable with the keyboard up: actions under the keyboard, no way to dismiss it, Next going nowhere, targets under 44pt |
| `currencies_test.dart` | the Dart currency list drifting from `shared/currencies.json`, and conversion disagreeing with the web and the database |
| `dashboard_currency_breakdown_test.dart` | the dashboard reconverting a base-currency total back into a foreign currency instead of showing the original entered amount; the `cash` / `opening` per-currency objects failing to parse; the rows losing their INR-first order |

---

## 5. Repository layout

```
context.md                  the specification
mindmap.md                  visual map of the same
db/
  migrations/0001…0012.sql  schema, engine, RLS, indexes, admin, currency
  seed.sql                  two isolated demo workspaces
  tests/                    accounting + RLS suites (self-rolling-back)
  tools/                    SQL runner and API smoke test
web/
  src/app/                  App Router: login, dashboard, people, activity, profile, admin
  src/lib/                  money, types, validation, queries, server actions
  src/components/           UI primitives, ledger sheets, shell
app/
  lib/core/                 config, money, dates, theme, failures
  lib/data/                 models + repositories (the only Supabase callers)
  lib/ui/                   screens, sheets, widgets, motion
  windows/installer/        Inno Setup script for the Windows installer
  test/                     money, contracts, and the UI regressions above
shared/
  currencies.json           the one currency definition every client is generated from
docs/                       security, performance, deployment, decisions, direction
```

---

## 6. Further reading

- [`docs/PROGRESS.md`](./docs/PROGRESS.md) — build status, file inventory, and what is left
- [`docs/decisions.md`](./docs/decisions.md) — why the non-obvious choices went the way they did
- [`docs/security.md`](./docs/security.md) — isolation model, admin separation, threat notes
- [`docs/performance.md`](./docs/performance.md) — measured numbers, and what made the client slow
- [`docs/deployment.md`](./docs/deployment.md) — migrations, Vercel, and how the binaries are cut
- [`docs/accounting-direction.md`](./docs/accounting-direction.md) — what credit and debit mean here
- [`docs/transfers-and-opening-balance.md`](./docs/transfers-and-opening-balance.md) — transfers, the opening balance as its own section, and the invariants both rest on

---

## 7. Deliberately not built

CRM · payroll · inventory · HR · tax/GST · invoicing · expense management ·
banking integrations · payment gateways · social login · public signup ·
push/email infrastructure · a reporting engine · full offline sync.

**Offline is about rates, not about writes.** Exchange rates are cached per owner and a
missing rate never blocks a save. Recording a transaction still needs the network, because
every balance is computed by the database and there is no local write queue — see
`context.md` §22.

The data layer is structured so offline sync can be added later without a rewrite
(`context.md` §22) — but v1 optimises for correctness, speed and a simple
architecture instead.
