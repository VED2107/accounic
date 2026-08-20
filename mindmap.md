# Accounting System — Mindmap

Companion to [`context.md`](./context.md). Same scope, visual form.
Every node traces back to a `context.md` section (§n).

---

## 1. Master Mindmap

```mermaid
mindmap
  root((Personal<br/>Accounting))
    Product §1 §35 §36
      Four questions
        Who do I deal with
        Who owes me
        Whom do I owe
        What is settled
      Philosophy
        Open → understand → record → settle
      Anti-scope
        No ERP
        No GST / payroll / inventory
        No payment gateway
    Clients
      Web §19
        Next.js App Router
        TypeScript strict
        RSC + Tailwind
      Flutter §20
        Android
        Windows desktop
        One codebase
      Rule §21
        One accounting engine
        No per-client math
    Backend
      PostgreSQL / Supabase
      RLS §3
      RPC / DB functions §12
      Auth email+password §2
    Data Model §11
      profiles
      people
      transactions
      settlements
    Accounting Engine §10
      Credit / receivable
      Debit / payable
      Settlements partial+full
      Derived balances
      minor units §7
    UX §13 §14 §15 §16 §18
      Dashboard
      Fast entry
      Global search
      Timeline
      Fintech feel not Excel
    Cross-cutting
      Security §24
      Performance §23
      Errors §26
      Loading §27
      Empty states §28
      Testing §33
    Roadmap §34
      P1 Foundation
      P2 Core accounting
      P3 Web
      P4 Flutter
      P5 Performance
      P6 Hardening
```

---

## 2. System Architecture (§21)

```mermaid
flowchart TB
    subgraph clients[Clients — no service-role key ever §24]
        W[Next.js Web]
        A[Flutter Android]
        D[Flutter Windows]
    end
    subgraph shared[Shared contract §21]
        C[Typed API / data contracts]
    end
    subgraph db[PostgreSQL / Supabase]
        AUTH[Auth: email + password §2]
        RLS[Row Level Security §3]
        FN[DB functions / RPC — balance engine §10 §12]
        T[(profiles · people · transactions · settlements)]
    end

    W --> C
    A --> C
    D --> C
    C --> AUTH
    C --> RLS
    RLS --> T
    FN --> T
    C --> FN
```

**Invariant:** balances are computed in one place (DB/RPC). Clients render, never re-derive. §10 §21

---

## 3. Data Model (§11)

```mermaid
erDiagram
    PROFILES ||--o{ PEOPLE : owns
    PROFILES ||--o{ TRANSACTIONS : owns
    PROFILES ||--o{ SETTLEMENTS : owns
    PEOPLE   ||--o{ TRANSACTIONS : has
    PEOPLE   ||--o{ SETTLEMENTS : has
    TRANSACTIONS ||--o{ SETTLEMENTS : "settled by (nullable)"

    PROFILES {
        uuid id PK
        text name
        text email
        text phone
        text business_name
        text currency
        text avatar_url
        timestamptz created_at
        timestamptz updated_at
    }
    PEOPLE {
        uuid id PK
        uuid owner_id FK
        text name
        text type "person | business"
        text phone
        text email
        text address
        text notes
        bool is_archived
        timestamptz created_at
        timestamptz updated_at
    }
    TRANSACTIONS {
        uuid id PK
        uuid owner_id FK
        uuid person_id FK
        text type "credit | debit"
        bigint amount_minor "paise, > 0"
        date transaction_date
        text description
        timestamptz created_at
        timestamptz updated_at
    }
    SETTLEMENTS {
        uuid id PK
        uuid owner_id FK
        uuid person_id FK
        uuid transaction_id FK "nullable = account-level"
        bigint amount_minor "> 0"
        date settlement_date
        text note
        timestamptz created_at
    }
```

### Constraints & indexes

| Kind | Rule | §ref |
|---|---|---|
| Check | `amount_minor > 0` | §12 |
| Check | `type in ('credit','debit')` | §11 |
| FK guard | person.owner_id = transaction.owner_id | §12 |
| FK guard | settlement.owner_id = transaction.owner_id | §12 |
| Business | settlement ≤ remaining (unless overpay allowed) | §12 |
| Preserve | never hard-delete settled history → archive/void | §17 |
| Index | `owner_id` | §23 |
| Index | `(owner_id, person_id)` | §23 |
| Index | `(owner_id, transaction_date desc)` | §23 |
| Index | `created_at` | §23 |

---

## 4. Accounting Model (§7 §8 §9 §10)

```mermaid
flowchart LR
    subgraph in[Inputs]
        CR[Credit tx<br/>they owe me]
        DR[Debit tx<br/>I owe them]
        ST[Settlement<br/>money moved]
    end
    subgraph engine[Engine — DB is source of truth]
        E1[Total Credit]
        E2[Total Debit]
        E3[Total Settled]
        E4[Outstanding Receivable]
        E5[Outstanding Payable]
        E6[Net Balance]
    end
    subgraph out[Views]
        P[Person page §6]
        G[Global totals §13]
    end
    CR --> E1 --> E4
    DR --> E2 --> E5
    ST --> E3 --> E4
    E3 --> E5
    E4 --> E6
    E5 --> E6
    E6 --> P
    E6 --> G
```

**Money rule §7:** integer minor units only. `₹100.50 → 10050`. No float in TS or Dart as source of truth.

### Settlement lifecycle (§9 §17)

```mermaid
stateDiagram-v2
    [*] --> Open: transaction created
    Open --> Partial: settlement < remaining
    Partial --> Partial: another partial
    Partial --> Settled: remaining hits 0
    Open --> Settled: full settlement
    Settled --> [*]: history preserved, never deleted
    Open --> Voided: archive/void (confirm required)
    Partial --> Voided: validate accounting state first
```

---

## 5. Security & Isolation (§3 §24 §25)

```mermaid
mindmap
  root((Security))
    Isolation §3
      RLS on every user-owned table
        profiles
        people
        transactions
        settlements
      owner_id on every row
      No frontend-only filtering
      Safe even against raw API calls
    Auth §2
      Email + password only
      No social login
      No public signup
      Admin creates users
      Session management
    Admin §25
      Add user
      Disable user
      Reset password
      Deactivate / delete
      Separated from user ops
      Role never client-settable
    Hygiene §24
      No service-role key in any client
      Server-side validation
      Input validation
      Rate limiting
      Audit-friendly records
```

**Threat cases to test §33:** cross-user person IDs, cross-user transaction IDs, unauthorized read, privilege escalation to admin.

---

## 6. Screen Map (§6 §13 §14 §15 §16 §29)

```mermaid
flowchart TD
    L[Login §2] --> DSH[Dashboard §13]
    DSH --> PPL[People list §5]
    DSH --> ACT[Recent activity §13]
    DSH --> ADD[Add transaction §14]
    SRCH[Global search §15] --> PD
    PPL --> PD[Person detail §6]
    PD --> TL[Timeline §16]
    PD --> ADD
    PD --> SET[Settle §9]
    DSH --> PRO[Profile §4]
    ADMIN[Admin area §25] --> USERS[Users CRUD]

    subgraph nav[Navigation §29]
        M["Mobile: Dashboard · People · Add · Activity · Profile"]
        DK["Desktop: Sidebar · Dashboard · People · Transactions · Overview · Settings"]
    end
```

### Person detail = the key screen (§6)

```text
Rahul Traders
You will receive  ₹18,500
You will pay      ₹6,000
Net balance       ₹12,500 receivable
────────────────────────────
timeline: credit / debit / settlement, newest first
```

Credit and debit live on **one** page. Never split into separate modules.

---

## 7. Core Flow (§36)

```mermaid
sequenceDiagram
    actor U as User
    participant C as Client (web/flutter)
    participant DB as Postgres + RLS

    U->>C: open app
    C->>DB: fetch totals (RPC)
    DB-->>C: receivable / payable / net
    U->>C: tap person
    C->>DB: person balance + timeline (paginated)
    DB-->>C: credit, debit, settled, outstanding
    U->>C: add credit ₹5,000
    C-->>U: optimistic update §14
    C->>DB: insert transaction (tx-wrapped)
    DB-->>C: confirmed balances
    U->>C: Settle ₹4,000
    C->>DB: insert settlement (validate ≤ remaining)
    DB-->>C: outstanding ₹1,000
    Note over C,DB: failure → "Balance has not been changed" §26
```

---

## 8. Quality Bars

```mermaid
mindmap
  root((Quality))
    Performance §23
      Fast app shell
      Paginated history
      Debounced search
      Composite indexes
      No N+1
      No huge payloads
      Measure not guess
    Code §32
      TS strict, no any
      Strong Dart types
      Repository pattern §20
      Centralized validation
      No duplicated business logic
    UX polish §18 §27 §28
      Skeletons everywhere
      Elegant empty states
      Subtle animation
      Keyboard on desktop
      Touch on mobile
    Errors §26
      Never silent
      No DB internals leaked
      State-accurate messages
    Offline §22
      Structure for it
      Do not build it in v1
```

### Test matrix (§33)

| Case | Input | Expected |
|---|---|---|
| Credit | +10,000 | outstanding 10,000 |
| Debit | +5,000 | outstanding 5,000 |
| Partial settle | 10,000 − 4,000 | 6,000 |
| Full settle | 10,000 − 10,000 | 0, history kept |
| Multiple | 10,000 + 5,000 − 3,000 | 12,000 |
| Mixed | credit 10,000 / debit 4,000 | net 6,000 receivable |
| RLS | user A reads B's row | denied |
| Escalation | user self-sets admin | denied |

---

## 9. Roadmap (§34)

```mermaid
flowchart LR
    P1[P1 Foundation<br/>repo · DB · auth · profiles · RLS · admin role · env]
    P2[P2 Core Accounting<br/>people · transactions · balances · settlements]
    P3[P3 Web<br/>login · dashboard · people · detail · add · settle · admin]
    P4[P4 Flutter<br/>models · auth · screens · desktop + android adapt]
    P5[P5 Performance<br/>indexes · queries · cache · pagination · bundles]
    P6[P6 Hardening<br/>security · RLS tests · integrity · edge cases · prod]
    P1 --> P2 --> P3 --> P4 --> P5 --> P6
```

### Deliverables checklist (§Deliverables)

- [ ] Architecture doc
- [ ] Schema + SQL migrations
- [ ] RLS policies
- [ ] Auth implementation
- [ ] Admin implementation
- [ ] Balance engine + settlement logic
- [ ] Next.js web app
- [ ] Flutter Android app
- [ ] Flutter Windows app
- [ ] Shared API/data contracts
- [ ] Tests (accounting + RLS)
- [ ] Seed/demo data
- [ ] `.env.example`
- [ ] Deployment instructions
- [ ] Performance notes
- [ ] Security notes

---

## 10. Out of Scope (§25 §30 §31 §35)

```text
✗ CRM          ✗ Payroll        ✗ Inventory
✗ HR           ✗ Tax / GST      ✗ Invoicing
✗ Expenses     ✗ Banking        ✗ Payment gateways
✗ Social auth  ✗ Public signup  ✗ Push/email infra
✗ Heavy reporting engine        ✗ Full offline sync in v1
```

If a feature does not answer one of the four questions in §35 — leave it out.
