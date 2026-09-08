# The Accounic Demo

The **same application** in `app/`, built with `--dart-define=DEMO_MODE=on`,
against **the same Supabase project** production uses, with a restricted feature
surface.

It is not a second app, a second frontend, a second database, or a second
accounting engine.

## There is no Flutter Web build

Not of the demo, and not of anything else. The Flutter codebase targets
**Android and Windows**; the browser client is the Next.js application in
`web/`. So the demo is distributed the way the product is — something you
install:

```
                       ONE Supabase project
                       ONE set of migrations
                       ONE accounting engine
                       ONE set of RLS policies
                                 |
     +----------------+----------+----------+----------------+
     |                |                     |                |
  Android          Windows              Web (web/)      Android + Windows
  real accounts    real accounts        real accounts   DEMO_MODE=on
     |                |                     |                |
     +----------------+---------------------+----------------+
                                 |
                    profiles.is_demo decides what the
                    interface offers this ACCOUNT.
                    RLS decides what the database will
                    hand over, and does not consult it.
```

Every tag publishes both families of build to the same GitHub release:

| | Real | Demo |
| --- | --- | --- |
| Android | `Accounic-<v>.apk` | `Accounic-demo-<v>.apk` |
| Windows | `Accounic-Setup-<v>-x64.exe`, portable zip | `Accounic-Demo-Setup-<v>-x64.exe`, portable zip |

The word `demo` in those names is load-bearing: `UpdateRepository` matches on
it, so a demo visitor is never offered the production installer and a paying
user is never offered the demo.

**Installing both is safe, and that is engineered rather than hoped for.** A
demo build is a different application to the machine it lands on:

| | Real | Demo |
| --- | --- | --- |
| Android application ID | `com.accounic.app` | `com.accounic.app.demo` |
| Android launcher name | Accounic | Accounic Demo |
| Windows AppId | `8B0E4C2A-…` | `3F7C1D9E-…` |
| Windows folder | `…\Programs\Accounic` | `…\Programs\Accounic Demo` |
| Supabase session key | `sb-<ref>-auth-token` | `sb-<ref>-auth-token-demo` |

The session key is the one that is easy to miss. Both builds point at the same
project, so supabase_flutter derives the same key from the URL — and on Windows
`getApplicationSupportDirectory()` comes from the executable's CompanyName and
ProductName, both "Accounic" either way, so the two share one SharedPreferences
file whatever folder they were installed into. Without the suffix, signing into
the demo would sign you out of your own ledger. `main.dart` sets it; the Android
side gets a separate sandbox from the application ID as well.

The Android identity is decided in `android/app/build.gradle.kts`, which reads
Flutter's `dart-defines` Gradle property to notice `DEMO_MODE=on`. That is what
keeps the production build command unchanged — no product flavour, no second
manifest.

## The demo never becomes the full product

A demo build is the demo for whoever is holding it. When an administrator
converts an account, the demo build does **not** quietly unlock — it shows
`UpgradedScreen` instead of the ledger: *your account is ready*, with the
direct download for their platform and the other platform beside it.

Letting the demo promote itself in place would leave a paying customer's books
on the build whose entire purpose is being a sample. Their account is real, so
they are sent to the application that is real too — same email, same password,
same books.

## Two flags, deliberately not one

| | Where it lives | What it decides |
| --- | --- | --- |
| **Build mode** | `AppConfig.demoMode`, compile-time, `--dart-define=DEMO_MODE=on` | That this build is a demo build: anonymous sign-in instead of a login form, and the restricted surface for everyone using it |
| **Account status** | `profiles.is_demo`, read through `me()` | Whether *this account* is a demo account, on any platform |

`demoRestrictedProvider` is the OR of the two. `demoAccountUpgradedProvider` is
the interesting combination: a demo BUILD holding a real ACCOUNT, which is the
person an administrator has just converted, and who gets shown the way out.

Collapsing the two flags would get both cases wrong: an administrator opening a
demo build is not a demo user, and a demo account signing in to the production
Windows application is still a demo account there.

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
node run-sql.mjs file ../migrations/0031_admin_set_demo.sql
```

Both go to the **real** project — that is the point of this architecture. They
are safe there:

- `0029` adds `demo_seed()` and `demo_reset()`, and both refuse any caller who
  is not a demo one.
- `0031` adds `admin_set_user_demo()`, the account-type edit in both
  directions.
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

## 4. Publish the demo builds

`.github/workflows/demo.yml` runs on a tag and attaches both demo builds to the
release the tag created, beside the production ones. It uses the release
workflow's own secrets — `SUPABASE_URL` and `SUPABASE_ANON_KEY` — because the
demo points at the same project.

By hand:

```
flutter build apk --release   --dart-define=DEMO_MODE=on   --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co   --dart-define=SUPABASE_ANON_KEY=your-anon-key

flutter build windows --release   --dart-define=DEMO_MODE=on   --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co   --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

The Windows job pins `windows-2022`, not `windows-latest`: the newer image ships
a Visual Studio that Flutter 3.29 does not recognise, so toolchain detection
falls back to "Visual Studio 16 2019" and CMake fails. `release.yml` already
knew this; `demo.yml` learned it on v1.13.1.

## 5. Find demo users in Administration

Both admin surfaces carry the same filter, because demo accounts are ordinary
accounts and belong in the ordinary directory:

- **Web** — `/admin`, the **Demo** tab (`?show=demo`).
- **Flutter** — Administration → the **Demo** segment.

Each row shows the name, email, demo status, people and transaction counts, and
when they were last seen. `Demo · anonymous` marks a visitor who arrived through
the hosted demo rather than with a password. The summary tile counts them.

## 6. Edit an account's type

An administrator creates both kinds of account and can change their mind. There
are two operations, deliberately, because they are two different acts:

| | Direction | Where |
| --- | --- | --- |
| **Convert to real user** | demo → real | Offered only on a demo account. Refuses a real one by name, so it cannot be misfired at a customer. Audited as `demo_user_converted`. |
| **Make it a demo account** | real → demo | Offered only on a real account. Refuses your own account. Audited as `demo_status_changed`. |

Neither touches a ledger row in either direction — not one person, transaction
or settlement is created, moved, converted or deleted. What changes is what the
interface offers that account.

Because there is one database, the change **is** the connection: the demo build
and the production build both read `profiles.is_demo` through `me()`, so an
account edited in Administration behaves differently the next time its client
loads its profile. There is no sync, no copy and nothing to keep in step.

## 7. Convert a demo user

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

## 8. Hand over the full application

After a conversion both admin surfaces offer **Copy app link**. The user signs
in with the same email and password they already had; `is_demo` is now false, so
the gates are gone. No second account, no second database, no data migration.

**Access is granted, never taken, and the demo does not pretend otherwise.**
There is no link a demo visitor can follow that gives them the full product, so
the demo offers none — no download, and deliberately no mail button either.
Launching someone's email client throws them out of the product mid-evaluation,
into an application that may not be configured, and dresses an administrative
decision up as a purchase form. Instead the demo states, in three numbered
steps, who grants access and what happens when they do.

**What the converted user gets.** The moment `is_demo` becomes false, Profile
grows an **Accounic on your devices** group offering the real installer for the
machine they are on — resolved to the exact release asset, not a page of files.
Web only, since on Android and Windows they are already holding it, and absent
entirely while the account is still a demo one.

So the flow ends where it should: they ask, an administrator enables the
account, and the next screen they look at hands them the application.

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

The production Android and Windows applications behave exactly as before for a
real account. `AppConfig.demoMode` is false unless the dart-define is passed, so
every build-mode branch is dead code the compiler removes;
`test/demo_mode_test.dart` asserts the default. `release.yml` is untouched, and
`web/` — the browser client for real accounts — is untouched.

A demo *account* is restricted on those platforms too, which is intended: the
restriction belongs to the account, and an administrator lifts it.
