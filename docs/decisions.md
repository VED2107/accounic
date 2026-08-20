# Design decisions

The choices in this build that were not obvious, and why they went the way they did.
Written down because the code shows *what* was done, not what was rejected.

---

## 1. Settlements carry a direction, not a sign

A settlement has `direction` (`in` / `out`) and a positive `amount_minor`, rather than a
signed amount.

`in` reduces outstanding receivable; `out` reduces outstanding payable. The alternative —
negative amounts on the transactions table — collapses two different events (a debt being
created, a debt being paid) into one row type, which makes "what is still outstanding"
require interpreting signs, and makes a partial payment indistinguishable from a credit
note.

`transaction_id` on a settlement is an **optional reference**, not a foreign-key-driven
allocation. Balances never depend on it. It means "the user pressed Settle on this row",
and it only biases display allocation.

## 2. Balances aggregate; per-row status is FIFO

Two different questions, answered two different ways:

- **What is outstanding?** Pure aggregation: `Σ credit − Σ settled-in`. Deterministic,
  index-friendly, and exactly what `context.md` §33's test cases specify.
- **Is *this invoice* settled?** `transaction_settlement_status()` allocates settlements
  across transactions: a settlement naming a transaction is applied there first, and any
  remainder spills onto the oldest still-open transaction of the same direction.

Keeping these separate matters. Making balances depend on allocation would mean every
dashboard number ran a loop; making per-row status a simple aggregate would mean the
timeline could not honestly say "₹6,500 left" on a specific invoice.

The targeted-before-FIFO rule exists for a concrete case: pressing Settle on a newer
invoice while an older one is open must credit the invoice the user clicked, not the
oldest one.

## 3. Money is bigint everywhere, and the views cast back

Amounts are integer minor units. The subtlety: `sum()` over `bigint` returns `numeric` in
PostgreSQL, and numeric reaches a client as a **decimal string**. That would reintroduce
exactly the floating-point-shaped hazard §7 forbids, one layer further out.

Every money expression in `0003_engine.sql` is therefore cast back to `bigint`. There is a
test asserting the dashboard's receivable arrives as a JSON *number*, and the Dart models
coerce defensively in case a future schema change reintroduces numeric.

## 4. Ownership is structural, not just policy

A child row proves it shares an owner through a **composite foreign key**
`(owner_id, person_id) → people(owner_id, id)`, not through a trigger or an RLS predicate
alone.

This holds even for service-role writes and bulk imports, where RLS is bypassed. RLS
protects the API; the composite FK protects the data.

## 5. `current_owner()` returns NULL rather than raising

Every RLS predicate is `owner_id = public.current_owner()`. For an anonymous or deactivated
caller that function returns `NULL`, so the predicate is `NULL` — never true.

The failure mode is "see nothing". Had it raised, a caller could distinguish "deactivated"
from "no rows", and any policy that forgot to handle the exception would fail open.

## 6. Admin membership lives in a table with no write policy

`app_admins` is separate from `profiles` specifically so that no column a user can update
determines their privilege. There is no insert/update/delete policy on it at all, so
`authenticated` cannot write to it by any route through PostgREST.

Admins deliberately get **no** read access to other users' ledgers. Administration is user
management; it is not a key to the books.

## 7. Deletion is not exposed

The API grants no `DELETE` on `transactions` or `settlements`. Void is the only path, and
voided rows stay visible in the timeline. Deleting a *person* is allowed only while they
have no transactions.

This is what makes "historical settlement relationships must not become corrupted"
(§17) enforceable rather than aspirational.

## 8. Over-settlement guards are deferred constraint triggers

They fire at end of statement, not per row, so a multi-row statement is judged on its final
state. Consequence worth remembering: the SQL test suites must issue
`set constraints all immediate`, because they roll back and never reach commit.

The same invariant is checked from the transaction side too — voiding or shrinking a
transaction can strand settlements above the basis just as easily as an oversized
settlement can.

## 9. One RPC per screen

`dashboard()` and `person_page()` return their whole payload as JSON in a single call
rather than the client issuing five queries. This is what makes the "no N+1, no huge
payloads" requirement (§23) structural instead of a discipline.

Corollary: `activity_page()` exists because `activity_feed` is a `UNION` view, and
PostgREST cannot embed a relationship through a view — it has no foreign-key metadata. The
join to `people` therefore has to happen server-side.

## 10. Colour carries exactly one meaning

Green means money coming in; rose means money going out. Nothing else in the UI is allowed
to use those hues decoratively, because the whole point of §8 is that direction should be
legible without reading a word.

This is why the Accounic brand gradient (blue → teal → green) stays confined to the logo,
and the UI accent takes the blue end rather than the green. A green "Save" button would
quietly compete with "you will receive".

## 11. Validation is three layers, and the database is the guarantee

Browser, then zod on the server, then CHECK constraints and RPC-level exceptions. A request
that bypasses the UI still meets the last two. Amounts are re-parsed server-side from raw
text — the client is never the authority on a number.

## 12. Money formatting is duplicated on purpose

`web/src/lib/money.ts` and `app/lib/core/money.dart` are deliberate mirrors, with mirrored
test suites asserting the same cases. Sharing them would mean a codegen step or a shared
package for ~150 lines; the tests are the cheaper guarantee. If the two ever disagree, a
user sees two different balances on two devices — so the tests, not the code, are the
contract.

## 13. Layout breakpoints are width-based, never platform-based

The Flutter shell switches between a navigation rail and a bottom bar at 900px of width,
not on `Platform.isWindows`. A Windows window dragged narrow behaves like a phone; an
Android tablet in landscape gets the rail. One rule, no per-platform branches.
