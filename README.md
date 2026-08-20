# Ledger

A small, fast, personal accounting system. Three clients, one backend, one database.

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
| Tenant isolation | `db/migrations/0005_rls.sql` | RLS on all four tables, forced |
| Admin operations | `db/migrations/0007_admin.sql` + `web/src/lib/admin-actions.ts` | service-role never leaves the server |
| Money representation | `money.ts` / `money.dart` | integer minor units, mirrored line for line |

---

## 2. The accounting model

Amounts are **integer minor units** (paise for INR). `₹100.50` is stored as `10050`.
No float, anywhere, ever, in the money path.

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
node db/tools/run-sql.mjs migrate       # 0001 … 0008
node db/tools/run-sql.mjs seed          # optional demo data
node db/tools/run-sql.mjs test          # 72 assertions, rolled back
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
| RLS / authorisation | (same command) | cross-tenant reads and writes, privilege escalation, disabled accounts, anon |
| End-to-end API | `node db/tools/smoke-api.mjs` | the real anon-key path: sign-in, RPCs, isolation |
| Web units | `cd web && npm test` | money parsing, formatting, balance meaning |
| Flutter units | `cd app && flutter test` | the same money cases, plus model/contract parsing |
| Types | `cd web && npm run typecheck` · `cd app && flutter analyze` | strict TS, zero analyzer issues |

The money suites in `web` and `app` deliberately assert the *same* cases. If they
ever disagree, a user is seeing two different balances on two devices.

---

## 5. Repository layout

```
context.md                  the specification
mindmap.md                  visual map of the same
db/
  migrations/0001…0008.sql  schema, engine, RLS, indexes, admin
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
  lib/ui/                   screens, sheets, widgets
  test/                     money and contract tests
docs/                       security, performance, deployment
```

---

## 6. Further reading

- [`docs/PROGRESS.md`](./docs/PROGRESS.md) — build status, file inventory, and what is left
- [`docs/decisions.md`](./docs/decisions.md) — why the non-obvious choices went the way they did
- [`docs/security.md`](./docs/security.md) — isolation model, admin separation, threat notes
- `docs/performance.md` — not yet written; measured numbers are in `PROGRESS.md` §6
- `docs/deployment.md` — not yet written

---

## 7. Deliberately not built

CRM · payroll · inventory · HR · tax/GST · invoicing · expense management ·
banking integrations · payment gateways · social login · public signup ·
push/email infrastructure · a reporting engine · full offline sync.

The data layer is structured so offline sync can be added later without a rewrite
(`context.md` §22) — but v1 optimises for correctness, speed and a simple
architecture instead.
