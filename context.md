# Build a Fast Multi-Platform Personal Accounting System

You are a senior full-stack/product engineer. Build a production-quality personal accounting system with **three clients sharing one backend and one database**:

1. **Web:** Next.js
2. **Android:** Flutter
3. **Desktop:** Flutter Desktop

Do NOT replace these technologies or argue for a different frontend stack.

The product is initially private software that will be provided only to a small number of trusted people/friends. However, the architecture must be clean, secure, scalable, and production-ready.

---

# 1. Core Product Concept

This is a simple personal/business accounting ledger.

Each owner/user has their own completely isolated accounting workspace.

A user should be able to:

- Add people/businesses they transact with
- Record money they need to receive
- Record money they need to pay
- See both credit and debit transactions from the same person/business page
- Record settlements/payments
- Automatically calculate outstanding balances
- Quickly understand who owes whom and how much
- View useful accounting summaries

Do NOT turn this into a giant ERP/accounting suite.

Keep the product focused on the workflow above.

The philosophy should be:

> **Open app → immediately understand money → record transaction in seconds → settle → everything stays accurate automatically.**

---

# 2. Multi-User Architecture

There will be multiple users.

An administrator creates user accounts.

Users will NOT have public registration.

Users should log in using:

- Email
- Password

Do NOT implement:

- Google login
- Facebook login
- GitHub login
- Apple login
- Social authentication
- Public signup

Authentication should use secure email/password authentication.

The admin should be able to:

- Create a user
- Set their email
- Set/reset their password
- Enable/disable a user
- View basic user information
- Delete/deactivate a user where appropriate

Users should only be able to access their own accounting data.

---

# 3. Tenant/Data Isolation

This is extremely important.

Every normal user effectively owns a private accounting workspace.

For example:

User A:

- Person A1
- Person A2
- Person A3
- Transactions
- Settlements
- Balances

User B:

- Person B1
- Person B2
- Transactions
- Settlements
- Balances

User A MUST NEVER be able to see, query, modify, or infer User B's accounting records.

Do not rely only on frontend filtering.

Enforce isolation at the PostgreSQL/database authorization layer using Row Level Security.

Every user-owned record must be associated with the appropriate owner/user/workspace ID.

Implement RLS policies for:

- People/businesses
- Transactions
- Settlements
- Profiles
- Any future user-owned accounting tables

The database must remain secure even if someone manually calls the API.

Never expose service-role/server secrets to web, Android, or desktop clients.

---

# 4. User Profile

Each user should have a basic profile.

Minimum fields:

- User ID
- Name
- Email
- Phone (optional)
- Business/shop name (optional)
- Profile image/avatar (optional)
- Currency
- Created date
- Updated date

Do not overbuild the profile system.

---

# 5. Person / Business Module

The central entity is a **Person/Business**.

A user can create a person/business such as:

- Customer
- Supplier
- Friend
- Vendor
- Company
- Any other person/business they transact with

Keep the terminology generic rather than forcing accounting-specific classifications.

Fields should include approximately:

- ID
- Owner/User ID
- Name
- Type: Person / Business
- Phone
- Email
- Address (optional)
- Notes (optional)
- Created date
- Updated date
- Active/archive status

The user should be able to search people/businesses quickly.

---

# 6. Person/Business Detail Page

This is one of the most important screens.

When opening a person/business, show BOTH:

### Credit

Money the user expects to receive.

Example:

> Customer owes me ₹10,000

### Debit

Money the user needs to pay.

Example:

> I owe supplier ₹5,000

Do NOT separate these into completely different modules.

They should be visible on the same person/business account page.

The page should make the net position immediately understandable.

Example:

```text
Rahul Traders

You will receive
₹18,500

You will pay
₹6,000

Net balance
₹12,500 receivable
```

Then show the transaction timeline.

---

# 7. Transaction Model

Every accounting transaction should contain at minimum:

- Transaction ID
- Owner/User ID
- Person/Business ID
- Direction/type
- Amount
- Date/time
- Note/description
- Created by
- Created timestamp
- Updated timestamp

Use precise monetary storage.

Prefer integer minor units such as paise rather than floating-point money values.

For INR:

```text
₹100.50 → 10050 paise
```

Never use JavaScript/Dart floating point arithmetic as the source of truth for financial amounts.

---

# 8. Credit / Debit

Use a very clear mental model.

### Credit / Receivable

The other party owes money to the user.

Example:

```text
Credit ₹5,000
Customer owes me ₹5,000
```

### Debit / Payable

The user owes money to the other party.

Example:

```text
Debit ₹3,000
I owe supplier ₹3,000
```

The UI must make this distinction extremely obvious.

Avoid confusing accounting terminology where it harms usability.

The software is for practical everyday accounting, not for teaching accounting theory.

---

# 9. Settlement System

Every outstanding transaction/account should have a prominent:

**Settle**

action.

Settlement means money was actually paid/received and the outstanding balance should decrease.

Example:

```text
Rahul Traders

You will receive: ₹10,000

[ Settle ₹10,000 ]
```

User can enter:

```text
Settlement amount: ₹4,000
Date: Today
Note: Cash received
```

After settlement:

```text
Original receivable: ₹10,000
Settled: ₹4,000
Remaining: ₹6,000
```

Support partial settlements.

Example:

```text
₹10,000
↓
₹3,000 settled
↓
₹7,000 remaining
```

A full settlement should result in:

```text
₹0 outstanding
```

but historical transactions must remain preserved.

Never delete the original transaction merely because it was settled.

---

# 10. Accounting Engine

Do not calculate balances independently in every frontend.

Create a centralized accounting model.

The database/backend should be the source of truth.

The system should automatically calculate:

```text
Total Credit
Total Debit
Total Settled
Outstanding Receivable
Outstanding Payable
Net Balance
```

For each person/business.

Also calculate global totals for the logged-in user:

```text
Total Receivable
Total Payable
Net Position
Today's Activity
Recent Transactions
```

All calculations must be deterministic and consistent across:

- Web
- Android
- Desktop

Do not implement three different accounting engines.

---

# 11. Recommended Data Model

Design a clean PostgreSQL schema.

A reasonable starting point:

```text
profiles
people
transactions
settlements
```

Potential structure:

### profiles

```text
id
name
email
phone
business_name
currency
avatar_url
created_at
updated_at
```

### people

```text
id
owner_id
name
type
phone
email
address
notes
is_archived
created_at
updated_at
```

### transactions

```text
id
owner_id
person_id
type
amount_minor
transaction_date
description
created_at
updated_at
```

Where:

```text
type = credit | debit
```

### settlements

```text
id
owner_id
person_id
transaction_id (nullable if supporting account-level settlement)
amount_minor
settlement_date
note
created_at
```

Do not blindly copy this schema if a better normalized accounting model is required.

The important requirement is that the final model must correctly support:

- Multiple users
- Multiple people/businesses
- Credit
- Debit
- Partial settlement
- Full settlement
- Historical records
- Accurate outstanding balances
- User isolation

---

# 12. Database-Level Accounting Integrity

Financial data must not depend on frontend calculations.

Use PostgreSQL constraints, transactions, indexes, and database functions/RPCs where useful.

Important rules:

- Amount must be positive
- Currency must be explicit
- Owner IDs must be validated
- Person must belong to the same owner
- Settlement must belong to the same owner
- Settlement cannot exceed the remaining amount unless explicitly supporting overpayment
- Deleted/archived entities must not corrupt historical records
- Financial history should be preserved

Use database transactions for operations that modify multiple related records.

---

# 13. Dashboard

The dashboard should be extremely simple.

Do not make it look like a traditional boring accounting application.

At the top:

```text
Good morning, Ved

Your money overview
```

Then large summary cards:

```text
Receivable
₹45,000

Payable
₹18,500

Net
₹26,500
```

Then:

```text
Recent activity
```

Show the latest transactions.

Then:

```text
People with outstanding balances
```

Show the most relevant people/businesses.

The dashboard should answer:

> "What is my current financial position?"

within a few seconds.

---

# 14. Fast Transaction Entry

This is a core UX requirement.

Adding a transaction should require as few steps as possible.

Example:

```text
+ Add transaction

Who?
[ Rahul Traders        ]

Type
[ Credit ] [ Debit ]

Amount
₹ [ 5,000 ]

Date
[ Today ]

Note
[ optional ]

[ Save transaction ]
```

After saving:

- Show confirmation
- Update balance immediately
- Update dashboard
- Update person account
- Do not require a full page reload

Use optimistic UI where safe.

---

# 15. Search

Global search should be extremely fast.

Search:

- Person/business name
- Phone
- Transaction note

The primary search should prioritize people/businesses.

Example:

```text
Search...

Rahul Traders
Rahul Patel
Rahul Electronics
```

Opening a result should immediately show the account.

---

# 16. Transaction Timeline

Person/business page should show a clean chronological timeline.

Example:

```text
Today

Credit
₹5,000
"Invoice #102"

Yesterday

Settlement
₹2,000
"Cash received"

12 Aug

Credit
₹8,000
"Previous order"
```

Each entry should clearly show:

- Type
- Amount
- Date
- Description
- Settlement status

Avoid clutter.

---

# 17. Editing and Deleting

Users should be able to edit incorrect transactions.

However, deleting financial records should require confirmation.

Prefer:

```text
Archive / Void
```

over destructive deletion where appropriate.

Historical settlement relationships must not become corrupted.

If a transaction already has settlements, editing/deleting it must validate the resulting accounting state.

---

# 18. UI/UX Direction

The application should NOT look like:

- Old accounting software
- Excel
- Government accounting software
- Generic admin dashboard

It should feel like a modern fintech/productivity application.

Design principles:

- Minimal
- Fast
- Calm
- Premium
- Extremely readable
- Strong typography
- Excellent spacing
- Subtle animations
- Clear hierarchy
- Excellent empty states
- Responsive
- Keyboard friendly on desktop
- Touch friendly on mobile

Use modern UI components where they genuinely improve usability.

Research current high-quality UI patterns from:

- shadcn/ui
- Radix UI
- Tailwind CSS
- Material 3
- Flutter Material 3
- modern fintech applications
- modern productivity applications

Do not blindly copy any existing product.

Create a unique visual language.

---

# 19. Web UI

Use modern Next.js architecture.

Prefer:

- Next.js App Router
- TypeScript
- React Server Components where beneficial
- Client Components only when interaction requires them
- Tailwind CSS
- Accessible component primitives
- Proper loading states
- Skeletons
- Streaming where useful
- Optimistic updates where safe
- URL-based navigation/state where appropriate

Use the current stable Next.js release rather than pinning an outdated version.

Performance is a first-class requirement.

---

# 20. Flutter Architecture

Build Android and Desktop from the same Flutter codebase.

Support:

- Android
- Windows desktop

Structure Flutter cleanly so business logic is shared.

Use:

- Strong typed models
- Repository pattern
- Centralized API/data layer
- State management appropriate for the application
- Local caching where useful
- Proper error/loading states

Do NOT create separate implementations of accounting logic for Android and Windows.

---

# 21. Shared Backend Contract

All three clients must use the same backend.

```text
             ┌──────────────────┐
             │   PostgreSQL     │
             │   / Supabase     │
             └────────┬─────────┘
                      │
          ┌───────────┴───────────┐
          │                       │
      Next.js                 Flutter
       Web                 Android/Desktop
```

The accounting rules must be identical everywhere.

Do not allow:

```text
Web calculates one balance
Android calculates another
Desktop calculates another
```

There must be one authoritative accounting model.

---

# 22. Offline/Connectivity Architecture

Design the client architecture so offline capability can be introduced without rewriting the product.

For Flutter especially, structure the repository/data layer so local persistence and synchronization can later be added.

However:

**Do not turn the first implementation into an unnecessarily complicated offline-sync system unless explicitly requested.**

The first version should prioritize:

1. Correctness
2. Speed
3. Reliability
4. Simple architecture

Build the foundation so offline sync is possible later.

---

# 23. Performance Requirements

Performance is a major product requirement.

Target:

- Very fast initial application shell
- Fast navigation
- Minimal unnecessary database queries
- Indexed database queries
- Paginated transaction history
- Debounced search
- Efficient list rendering
- Optimistic UI for safe mutations
- Cached profile/account data
- No unnecessary global state
- No unnecessary API requests
- No N+1 queries
- No huge payloads

Database indexes should exist for common access patterns, such as:

```text
owner_id
person_id
owner_id + person_id
transaction_date
created_at
```

Use composite indexes where query patterns justify them.

Measure performance instead of guessing.

---

# 24. Security Requirements

Treat accounting data as sensitive.

Implement:

- Secure authentication
- Strong password handling
- Session management
- Database RLS
- Authorization checks
- Server-side validation
- Input validation
- Rate limiting where appropriate
- No secrets in client applications
- No service-role key in frontend/mobile/desktop
- Secure environment variables
- Audit-friendly financial records

Admin operations must be separated from normal user operations.

A normal user must never be able to turn themselves into an admin by modifying client-side state.

---

# 25. Admin Panel

Create a separate admin area.

Admin should be able to:

```text
Dashboard

Users
├── Add user
├── View users
├── Disable user
├── Reset password
└── Delete/deactivate user

Basic system information
```

Keep the admin panel intentionally small.

Do not build unnecessary:

- CRM
- Payroll
- Inventory
- HR
- Tax management
- Invoicing
- GST management
- Expense management
- Banking integrations
- Payment gateways

unless specifically requested later.

---

# 26. Error Handling

Never silently fail.

For example:

If settlement fails:

```text
Settlement could not be completed.
Your balance has not been changed.
```

If transaction creation fails:

```text
Transaction was not saved.
Please try again.
```

Show useful errors without exposing database internals.

---

# 27. Loading States

Every important operation needs a polished loading state.

Examples:

- Dashboard skeleton
- Person list skeleton
- Transaction list skeleton
- Button loading state
- Settlement processing state
- Login loading state

Avoid flashing empty screens.

---

# 28. Empty States

Create useful empty states.

Example:

```text
No people yet

Add your first person or business
to start tracking money.

[ + Add person ]
```

For no transactions:

```text
No transactions yet

Your activity will appear here.
```

Keep empty states visually elegant.

---

# 29. Responsive UX

Web:

- Desktop
- Laptop
- Tablet
- Mobile browser

Flutter:

- Android phones
- Windows desktop

The desktop UI should take advantage of available screen space.

Mobile should prioritize:

```text
Dashboard
People
Add transaction
Activity
Profile
```

Desktop can use:

```text
Sidebar
Dashboard
People
Transactions
Reports/Overview
Settings
```

Do not create unnecessary navigation items.

---

# 30. Useful Reporting — But Keep It Small

Only include reporting that directly helps this accounting workflow.

Useful:

### Overall balance

```text
Receivable
Payable
Net
```

### Person balance

```text
Credit
Debit
Settled
Outstanding
```

### Activity

```text
Daily / weekly / monthly transaction activity
```

Do not build a complicated accounting reporting engine in v1.

---

# 31. Notifications

Do not build a huge notification system.

Only create the architecture for useful future reminders such as:

```text
Outstanding balance
Settlement reminder
```

Do not implement unnecessary push/email notification infrastructure unless required.

---

# 32. Code Quality

Use:

- TypeScript strict mode
- Strong typing
- Clean component boundaries
- Reusable UI components
- Centralized validation
- Centralized accounting logic
- Clear repository structure
- Meaningful naming
- Small focused functions
- No duplicated business logic
- No magic numbers
- No `any` unless absolutely unavoidable

Flutter should also use strong typing and clean architecture.

---

# 33. Testing

Write tests for the accounting engine.

At minimum test:

### Credit

```text
Credit ₹10,000
Outstanding = ₹10,000
```

### Debit

```text
Debit ₹5,000
Outstanding = ₹5,000
```

### Partial settlement

```text
Credit ₹10,000
Settlement ₹4,000
Outstanding = ₹6,000
```

### Full settlement

```text
Credit ₹10,000
Settlement ₹10,000
Outstanding = ₹0
```

### Multiple transactions

```text
Credit ₹10,000
Credit ₹5,000
Settlement ₹3,000

Outstanding = ₹12,000
```

### Mixed account

```text
Credit ₹10,000
Debit ₹4,000

Net = ₹6,000 receivable
```

Also test:

- RLS isolation
- Unauthorized access
- Cross-user person IDs
- Cross-user transaction IDs
- Settlement validation
- Admin permissions

---

# 34. Development Order

Do not build everything simultaneously without a plan.

Implement in this order:

## Phase 1 — Foundation

- Repository structure
- Database
- Authentication
- Profiles
- RLS
- Admin role
- Environment configuration

## Phase 2 — Core Accounting

- People/businesses
- Transactions
- Credit/debit
- Balance calculations
- Settlements
- Partial settlement
- Transaction history

## Phase 3 — Web

- Login
- Dashboard
- People
- Person detail
- Add transaction
- Settlement
- Profile
- Admin

## Phase 4 — Flutter

- Shared models
- Authentication
- Dashboard
- People
- Person detail
- Transaction creation
- Settlement
- Desktop adaptation
- Android adaptation

## Phase 5 — Performance

- Database indexes
- Query optimization
- Caching
- Pagination
- Optimistic mutations
- Bundle optimization
- Flutter rendering optimization

## Phase 6 — Hardening

- Security audit
- RLS tests
- Authorization tests
- Accounting integrity tests
- Error handling
- Edge cases
- Production configuration

---

# 35. Important Product Rule

Do not over-engineer the first version.

The application should primarily answer four questions:

1. **Who do I have an account with?**
2. **How much do they owe me?**
3. **How much do I owe them?**
4. **What has been settled and what remains?**

Everything in the first version should support those questions.

If a proposed feature does not directly improve those workflows, leave it out.

---

# 36. Final UX Goal

The final experience should feel closer to a modern personal finance/productivity application than traditional accounting software.

A user should be able to:

```text
Open app
    ↓
See total receivable/payable
    ↓
Tap person
    ↓
Immediately understand balance
    ↓
Add credit/debit in seconds
    ↓
Later tap Settle
    ↓
Balance automatically updates
```

No unnecessary complexity.

No confusing accounting terminology.

No duplicated logic between platforms.

No security shortcuts.

No bloated ERP functionality.

Build a **small, extremely fast, polished, reliable accounting system** first, with architecture that can grow later.

---

# Deliverables

Before considering the implementation complete, provide:

1. Final architecture
2. Database schema
3. SQL migrations
4. RLS policies
5. Authentication implementation
6. Admin implementation
7. Accounting/balance engine
8. Settlement logic
9. Next.js web application
10. Flutter Android application
11. Flutter Windows desktop application
12. Shared API/data contracts
13. Tests
14. Seed/demo data
15. Environment configuration example
16. Deployment instructions
17. Performance notes
18. Security notes

Do not merely create mock screens.

All important flows must work end-to-end against the real database.

Start by designing the data model and accounting invariants, then implement the backend/security foundation, then the web client, then the Flutter clients.
