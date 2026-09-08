# Accounic Online Demo

A hosted Flutter Web build of **the same application** in `app/`, against **the
same Supabase project** production uses, with a restricted feature surface.

It is not a second app, a second frontend, a second database, or a second
accounting engine. It is `app/` with `--dart-define=DEMO_MODE=on`.

## The architecture in one picture

```
                       ONE Supabase project
                       ONE set of migrations
                       ONE accounting engine
                       ONE set of RLS policies
                                 |
      +--------------------------+--------------------------+
      |                          |                          |
 Android / Windows          Web (production)            Web (demo build)
 real accounts              real accounts               DEMO_MODE=on
      |                          |                          |
      +--------------------------+--------------------------+
                                 |
                    profiles.is_demo decides what the
                    interface offers this ACCOUNT.
                    RLS decides what the database will
                    hand over, and does not consult it.
```

Real users → real Supabase. Demo users → the same Supabase, with
`is_demo = true`. An administrator converts one to the other, and the account,
the password and the books all stay exactly where they are.

## Two flags, deliberately not one

| | Where it lives | What it decides |
| --- | --- | --- |
| **Build mode** | `AppConfig.demoMode`, compile-time, `--dart-define=DEMO_MODE=on` | Which door the visitor arrives at — anonymous sign-in instead of a login form |
| **Account status** | `profiles.is_demo`, read through `me()` | Whether *this account* gets the restricted experience, on any platform |

`demoRestrictedProvider` is the OR of the two and is the only question a feature
gate asks. Collapsing them would get both cases wrong: an administrator opening
the demo build is not a demo user, and a demo account signing in to the Windows
application is still a demo account there.

## Isolation

**Unchanged, and not weakened anywhere.** A demo account is confined by exactly
the predicates a paying account is confined by — `owner_id = current_owner()`.
There is no demo branch in any RLS policy, `0030_demo_users.sql` adds none, and
the client does no filtering of its own. A demo user cannot see another demo
user, a real user, or an administrator, and nor can the demo build.

Anonymous sign-in gives each visitor to the hosted demo their own `auth.users`
row, so each of them gets a private workspace for the same reason every customer
does.

## What is never in the browser

The Flutter build carries the **publishable (anon) key** and nothing else. Every
privileged operation stays where it already was:

- Creating a user, resetting a password → Next.js server actions, service-role
  key, `web/src/lib/admin-actions.ts`.
- Listing users, enabling, disabling, converting → `SECURITY DEFINER` RPCs that
  re-check `is_admin()` in their own bodies, callable with the anon key by an
  administrator and by nobody else.

`is_demo` cannot be set by any client. Making a demo account needs the
service-role key; clearing it needs `admin_convert_demo_user()` and an
administrator. There is no client route to either.

## The accounting engine

One engine, no exceptions. A demo transaction takes the identical path a real
one takes:

```
transaction model → LedgerRepository → create_transaction() → the engine → balance
```

`demo_seed()` builds the sample books by calling `create_person()`,
`create_transaction()` and `create_settlement()` — the real
`SECURITY INVOKER` RPCs — so even the sample data is written *by* the engine
rather than inserted beside it. There is no `DemoBalanceCalculator`,
`DemoTransactionEngine` or `DemoSettlementEngine`, and there must never be one.

---

# Running it

## 1. Apply the migrations

```
cd db/tools
node run-sql.mjs file ../migrations/0029_demo.sql
node run-sql.mjs file ../migrations/0030_demo_users.sql
```

Both go to the **real** project — that is the point of this architecture. They
are safe there:

- `0029` adds `demo_seed()` and `demo_reset()`, and both refuse any caller who
  is not a demo one.
- `0030` adds `profiles.is_demo` (defaulting to **false**, so every existing
  account is a real account), the administration surface, and
  `admin_convert_demo_user()`, which **refuses** a target that is not currently
  a demo account.
- `handle_new_auth_user()` gains a synthetic address for anonymous users. The
  path a named user takes through it is unchanged.

Then enable **Anonymous sign-ins**: Dashboard → Authentication → Providers →
Anonymous. Cap them under Authentication → Rate Limits; every anonymous visitor
becomes a row in the real project, so the ceiling matters here in a way it would
not in a throwaway one.

## 2. Create the demo account

```
cd db/tools
SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=... \
node demo-account.mjs demo@accounic.app 'AccounicDemo2026'
```

Omit the email and password and it uses `demo@accounic.app` with a generated
password, and prints both. Re-runnable: an existing account has its password
reset and its flag re-applied, and its books are left alone.

An administrator can equally create one from the web admin — **Add user →
Account type → Demo user**. That is the only other place a demo account is ever
made, and it is there because it needs the service-role key.

## 3. Seed or reset demo data

Seeding happens on its own: the demo build calls `demo_seed()` after sign-in,
and it is a no-op on a workspace that already has people. A visitor puts the
books back from **Profile → Reset demo data**, which calls `demo_reset()` —
`void_person_history()` and `delete_person()` per account, then `demo_seed()`
again. All production RPCs.

## 4. Deploy the web demo

`.github/workflows/demo.yml` builds and publishes to GitHub Pages. Two
repository secrets, both from the real project:

- `DEMO_SUPABASE_URL`
- `DEMO_SUPABASE_ANON_KEY`

Optionally `FULL_APP_URL`, if the full application lives somewhere other than
the releases page. Enable Pages with source "GitHub Actions".

By hand:

```
flutter build web --release \
  --dart-define=DEMO_MODE=on \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=UPDATE_CHECK=off \
  --base-href=/accounic/
```

## 5. Find demo users in Administration

Both admin surfaces carry the same filter, because demo accounts are ordinary
accounts and belong in the ordinary directory:

- **Web** — `/admin`, the **Demo** tab (`?show=demo`).
- **Flutter** — Administration → the **Demo** segment.

Each row shows the name, email, demo status, people and transaction counts, and
when they were last seen. `Demo · anonymous` marks a visitor who arrived through
the hosted demo rather than with a password. The summary tile counts them.

## 6. Convert a demo user

Menu → **Convert to real user** → confirm.

The confirmation states this account's own people and transaction counts, so an
administrator knows before they click that **the demo books become the real
books**. Nothing is deleted, ever, by this operation.

`admin_convert_demo_user()` refuses unless:

1. the caller is an administrator,
2. the target exists,
3. the target is currently `is_demo = true` — a real account is **refused**, not
   silently ignored,
4. the target is not anonymous — an anonymous visitor has no email and no
   password, so converting them would leave a real account nobody can sign in
   to.

It writes an `admin_events` row (`demo_user_converted`) naming the
administrator, the target, the time, and the counts that came through.

If you later want *convert and start fresh*, that is a separate operation and it
has to be designed and asked for by name. This one never discards a ledger.

## 7. Hand over the full application

After a conversion both admin surfaces offer **Copy app link**. The user signs
in with the same email and password they already had; `is_demo` is now false, so
the gates are gone. No second account, no second database, no data migration.

The address comes from one constant — `AppConfig.fullAppUrl`, overridable with
`--dart-define=FULL_APP_URL=…` — read by the gate sheet, the demo screen, the
masthead and the administrator's confirmation.

---

## What the demo restricts

Restriction is presentation-layer only. Every gated capability still exists in
the binary and still works against the engine; the demo routes to
`showUpgradeSheet()` instead.

| Gated | Why |
| --- | --- |
| Reports and exports (PDF, CSV, JSON) | The full product's deliverable |
| Transfers between people | Advanced ledger workflow |
| Targeted settlement allocation | Advanced settlement engine |
| Foreign-currency entry and manual rates | Full multi-currency accounting |
| Opening balances | Advanced account management |
| Administration | Refused by `is_admin()`, not by the interface |

Basic settlement is deliberately **not** gated: it is the workflow the demo
exists to demonstrate, and it runs through the real `create_settlement()`.

## What this does not change

The Android and Windows applications behave exactly as before for a real
account. `AppConfig.demoMode` is false unless the dart-define is passed, so
every build-mode branch is dead code the compiler removes;
`test/demo_mode_test.dart` asserts that default. The release workflow is
untouched.

A demo *account* is restricted on those platforms too, which is intended: the
restriction belongs to the account, and an administrator lifts it.
