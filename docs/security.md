# Security notes

Accounting data is treated as sensitive (`context.md` §24). This is what protects it,
and what does not.

---

## 1. The isolation model

**Claim:** with a valid anon key and a raw HTTP client, a signed-in user can reach
only rows whose `owner_id` is their own active user id.

Nothing in that claim depends on the frontend. The web app could be replaced with
`curl` and the boundary would hold.

How it is built:

| Layer | Mechanism |
|---|---|
| Row visibility | RLS `ENABLE` + `FORCE` on `profiles`, `people`, `transactions`, `settlements` |
| Predicate | `owner_id = public.current_owner()` on select/insert/update |
| Session identity | `current_owner()` returns `auth.uid()` only when the profile is active, else `NULL` |
| Structural ownership | composite FKs `(owner_id, person_id)` and `(owner_id, transaction_id)` — a child row cannot reference another workspace's parent even from the service role |
| Anonymous role | all grants revoked; `anon` reaches no table, view or RPC |

Because `current_owner()` returns `NULL` rather than raising for an invalid session,
every policy predicate evaluates to false. The failure mode is "see nothing", not
"see everything".

### Deactivation is enforced by the database

Disabling a user sets `profiles.is_active = false`. Their JWT may still be
cryptographically valid until it expires — so the check is not "can they log in",
it is `current_owner()` returning `NULL` for them. Their existing session stops
returning data immediately, and every write RPC refuses.

Verified by `db/tests/02_rls_isolation.sql`: a disabled user reads zero people,
cannot insert, cannot call a write RPC, cannot load the dashboard.

---

## 2. Privilege separation

Admin membership lives in its own table, `app_admins`, and **has no write policy at
all**. `authenticated` can read only their own row, to decide whether to render the
admin nav. There is no route through PostgREST by which a user can insert into it.

`grant_admin()` / `revoke_admin()` are `SECURITY DEFINER` with execute revoked from
`public`, `anon` and `authenticated` — service role only.

A trigger additionally rejects any self-service change to `profiles.is_active` or
identity columns, so "make myself an admin" and "re-enable myself" both fail even
if a policy were ever loosened by mistake.

**Admins cannot read other users' books.** There is deliberately no policy granting
them access to another workspace's ledger, and no admin RPC returns one. Admin means
user management, not omniscience.

Tested: `user cannot make themselves an admin`, `user cannot call grant_admin`,
`non-admin cannot list users`, `admin still cannot see another user's transactions`.

---

## 3. Secrets

| Secret | Where it lives | Where it must never go |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Next.js server env only | any browser bundle, the Flutter app, git |
| Anon / publishable key | all three clients | — safe by design; RLS bounds it |
| `DATABASE_URL` | local `.env.local`, CI secrets | any client |

`web/src/lib/supabase/admin.ts` is the only module that constructs a service-role
client. It imports `server-only`, so importing it from a Client Component is a build
error rather than a runtime leak. The key is read from a non-`NEXT_PUBLIC_` variable,
so it cannot reach the browser even by accident.

The Flutter binaries receive configuration through `--dart-define` and hold only the
publishable key. A mobile or desktop binary is not a secret store.

---

## 4. Authentication

Email and password only. No social providers, no public signup, no self-service
password reset — an administrator creates accounts and resets passwords
(`context.md` §2).

- Sign-in failures return one message for "no such user" and "wrong password", so the
  form cannot be used to enumerate accounts.
- Password rules are identical in all three places that set one (user profile, admin
  create, admin reset): ≥10 characters with upper, lower and a digit.
- `getUser()` is used server-side rather than `getSession()`: the former revalidates
  the JWT with the auth server, the latter trusts a cookie the client could have
  written.
- Sessions refresh in middleware; the middleware is a convenience redirect, not the
  security boundary.

---

## 5. Financial integrity

Rules the database will not let any client break (`context.md` §12):

- `amount_minor > 0` and bounded well below the 64-bit limit
- a person, transaction and settlement on one row must share an owner
- a settlement naming a transaction must match its person and its direction
  (credit is settled by money in; debit by money out)
- total settled per direction can never exceed total transacted — enforced by a
  deferred constraint trigger, so a multi-row statement is judged on its final state
- the same invariant is checked from the transaction side: you cannot void or shrink
  a transaction and strand settlements above it
- `owner_id` and `person_id` on a financial row are immutable; a voided row cannot be
  edited
- deletion of a person with history is refused — archive instead
- the API exposes no `DELETE` on `transactions` or `settlements` at all; `void` is the
  only path, and voided rows stay visible as history

Every one of these has a test in `db/tests/01_accounting_engine.sql` asserting that
the operation is **rejected**.

---

## 6. Input handling

Three layers, in this order, and the last one is the guarantee:

1. the browser / widget, for fast feedback,
2. zod (`web/src/lib/validation.ts`) on the server, before any RPC call,
3. `CHECK` constraints and RPC-level `raise exception` in PostgreSQL.

A request that bypasses the UI entirely still meets 3. Amounts are re-parsed
server-side from the raw text; the client is never the authority on a number.

Error messages are translated (`web/src/lib/errors.ts`, `app/lib/core/failure.dart`)
so users see sentences and never table names, constraint names or SQL. Full detail is
logged server-side only.

---

## 7. Known limits

Honest about what is **not** covered:

- **No rate limiting in the app.** Supabase's platform limits apply to auth; there is
  no application-level throttle on RPCs. For a handful of trusted users this is
  acceptable; a public deployment would need one.
- **No audit log table.** Records are audit-*friendly* — `created_by`, timestamps, and
  void-instead-of-delete mean history is reconstructable — but there is no separate
  immutable audit trail of who changed what.
- **No MFA.** Not offered by the spec's auth scope.
- **Admin deletion is real.** `adminDeleteUser` cascades and destroys that user's
  entire ledger. It is confirmed in the UI and refuses self-deletion, but it is not
  recoverable. Disabling is the default path.
- **Demo seed users.** `db/seed.sql` creates `demo@example.com` and
  `friend@example.com` with a known password. Delete them before any real use.

---

## 8. Re-running the checks

```bash
node db/tools/run-sql.mjs test    # 38 authorisation assertions, in-transaction, rolled back
node db/tools/smoke-api.mjs       # the same boundary over real HTTP with the anon key
```

Both are safe against a live database: the SQL suite rolls back, and the smoke test
cleans up after itself.
