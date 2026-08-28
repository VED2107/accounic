# Transfers, and the opening balance as its own thing

The v1.6.0 accounting-model upgrade, in one place: what changed, why it is shaped the
way it is, and which invariants hold.

Three migrations, all additive, none of which rewrites a single stored figure:

| File | What it does |
|---|---|
| `db/migrations/0019_opening_balance.sql` | the opening balance stops being a timeline row |
| `db/migrations/0020_transfers.sql` | money moves between two people as one transaction |
| `db/migrations/0021_settle_opening_balance.sql` | the opening balance gets its own way of being settled |

---

## 1. The opening balance

### What was wrong

Since `0010` an opening balance has been a transaction carrying `is_opening`. That was
the right **storage** decision and it stays: the balance engine then computes the
position correctly by construction, with no second code path and no second place for the
arithmetic to drift.

It was the wrong **presentation** decision. `person_page()` served the opening row inside
`timeline`, beside the credits and debits, so a balance carried in from before the
account existed showed up as something that happened on a Tuesday, wore a Credit or Debit
label, and offered a *Settle this* button. A user could settle their own opening balance
as though somebody had paid it.

### What it is now

```
Opening balance          its own section, its own actions (settle, edit, remove)
  400 AED
  ≈ ₹10,393.69 INR
  1 AED = ₹25.984225 INR

Regular transactions     credits, debits, transfers, settlements
  Credit  $40 USD
          ≈ ₹3,817.11 INR
```

* `public.person_opening` — one view answering "what did this account open with, in what
  currency, at what rate, and what is that worth in base?". At most one row per person;
  `0010`'s unique index guarantees it.
* `person_page()` returns `opening` and `opening_history`, and `timeline` no longer
  carries opening rows at all. `timeline_total` counts what the timeline actually holds.
* `open_transactions` excludes opening rows, so no screen can offer *Settle this* against
  one.
* `validate_settlement_row()` **refuses** a settlement that names an opening balance from
  any route but the dedicated one below. The UI change is a convenience; this is the
  guarantee.

### Settling it — its own path, in its own section (`0021`)

`0019` was right to stop the opening balance being settled through the ordinary
*Settle this* row action, and went one step too far: it refused every settlement naming
one, which left a real event — somebody paying off specifically what the account opened
with — nowhere to be recorded.

So each section now has its own way of being settled, on one page:

| Section | Action | Settles |
|---|---|---|
| Opening balance | **Settle** | that entry, and only that |
| Regular transactions | **Settle** / **Settle this** | the whole account, or one row |

* `settle_opening_balance()` is the **only** route by which a settlement may name an
  opening balance. It derives the direction from the opening entry rather than accepting
  one — a balance the person owes is retired by money coming in, and one the user owes by
  money going out — which is the single mistake this path exists to make impossible. The
  amount defaults to whatever is left of it.
* The permission is a **transaction-local GUC** that only that function sets, carrying the
  person id so the exemption applies to the account being settled and to no other. A
  client cannot send it, and it disappears with the transaction, so it cannot leak onto
  the next request on a pooled connection. `create_settlement()` is refused exactly as it
  was — `db/tests/09` asserts the refusal both before and immediately after a successful
  dedicated settlement.
* `person_opening` carries `settled_minor`, `remaining_minor` and `status`, resolved by
  the same FIFO allocator every other row reads, so the section shows where its own
  settlement stands without recomputing anything.

Settling is not editing: the opening balance's own amount, currency, rate and date are
untouched, and `person_balances.opening_minor` does not move. What moves is the position.

### What did not change

The opening balance still flows through `person_balances` exactly as before. It is still
a transaction, it is still summed into `total_credit` / `total_debit`, and `net_balance`
is the same integer after the migration as before it. An account-level settlement still
retires it along with everything else outstanding — which is correct, because it is real
money owed. What is refused is settling it through the *generic* transaction path —
`create_settlement()` and the row action — rather than through the section's own.

### Historical data

`0019 §1` reclassifies opening balances that predate the flag. It changes `is_opening` on
an existing row and nothing else — same id, same amount, same currency, same rate, same
date — and only when every one of these holds:

* the row is not void,
* its description is exactly "opening balance", ignoring case and padding,
* the person has no non-void opening balance already,
* it is that person's oldest transaction,
* it is the only such candidate on that account.

It inserts nothing, and a row failing any test is left exactly as it is rather than
guessed at. Running it twice reclassifies nothing the second time — pinned by
`db/tests/09_opening_balance_section.sql`.

In practice there was nothing to reclassify on the live database: every opening balance
this product has ever written came from `set_person_opening_balance()` or
`create_person()`, and both set the flag. The block exists for the hand-entered case and
says out loud how many it found.

---

## 2. Transfers

```
Ved   ₹10,000        transfer ₹3,000        Ved   ₹7,000
Dhruv  ₹2,000        Ved → Dhruv            Dhruv ₹5,000
```

and the workspace total does not move, because nothing entered or left it.

### The model

A transfer is **one logical record** (`public.transfers`) realised as exactly **two
linked ledger entries** — ordinary rows in `public.transactions` carrying `transfer_id`
and `transfer_role`:

| Role | Type | On | Effect |
|---|---|---|---|
| `source` | `debit` | the FROM person | net position falls |
| `destination` | `credit` | the TO person | net position rises |

Ordinary rows on purpose. `person_balances`, `owner_summary`, the FIFO settlement
allocator, the activity feed, the per-currency dashboard totals and every index already
know what a transaction is, and a transfer made of them is correct in all of those by
construction rather than by a second implementation that has to be kept in step. This is
the same device `0010` used for the opening balance, and for the same reason.

The stored enum labels run backwards to the spoken words — see
[`accounting-direction.md`](./accounting-direction.md). `debit` is the direction that
*reduces* a person's net position, which is what leaving the source account means.

### What makes the pair one thing

* both legs carry the same `transfer_id`;
* `(transfer_id, transfer_role)` is unique, so there is exactly one source and one
  destination and a third leg cannot exist;
* a **deferred constraint trigger** (`assert_transfer_intact`) checks at every commit that
  the two legs still agree with their transfer row about person, direction, amount and
  void state.

That last one is what makes "one side can never remain without the other" true rather
than merely intended. It holds against any writer — RPC, PostgREST, or `psql`. Voiding one
leg by hand fails the commit with *"Both sides of a transfer are voided together or not
at all."*

> **A defect worth recording.** The first version of that trigger read
> `case when tg_table_name = 'transfers' then new.id else new.transfer_id end`. A CASE is
> one SQL expression, so PL/pgSQL resolves *every* field reference in it — including the
> branch not taken — and the `transfers` table has no `transfer_id` column. Every transfer
> raised `record "new" has no field "transfer_id"`, and because the trigger is deferred it
> did so at commit rather than at the insert that caused it. It was invisible until
> `db/tests/10_transfers.sql` fired the deferred checks explicitly with
> `set constraints all immediate`. A deferred check that is never fired is a check that
> proves nothing, which is why that suite fires them at two points rather than relying on
> a commit it never reaches.

### Currencies

The amount is entered in one currency and reaches the destination in two documented
steps, each **skipped** when its two currencies are the same — which is the ordinary case
and costs nothing:

```
entry currency --entry_rate_e9--> source ledger --exchange_rate_e9--> destination ledger
```

Every rate used is stored on the transfer and frozen there. A later market move never
rewrites it, and no read path re-derives a stored amount from a current rate.
`conversion_mode = 'manual'` records what actually arrived when the counter handed over
something other than what the rate said — the same override `0014` added to every other
money RPC, applying to the second step only, because that is where a spread lives.

### Reconciliation

| Case | Guarantee | Enforced by |
|---|---|---|
| same currency both sides | `from_amount_minor = to_amount_minor` exactly | `transfers_same_currency_equal` CHECK |
| different currencies | `to_amount_minor` is what the stored rate says | `transfer_integrity` view |
| every transfer | source impact + destination impact = 0 in the transfer's own terms | both of the above |
| every workspace | `dashboard INR total = Σ person INR balances` | `owner_summary`, pinned by tests 08 and 10 |

`public.transfer_integrity` lists every live transfer whose two sides fail to reconcile.
**It should always be empty**; a row in it is a defect, not a warning. It is a view rather
than a test so it can be run against production data at any time.

One honest caveat. The dashboard's base-currency figure converts each person's position at
*today's* cached rate, as it has since `0010`. So a **cross-currency** transfer can move
that display total when the market moves — not because the transfer changed, but because
the display conversion did. Nothing settles against that figure and no stored amount is
ever recomputed from it. For a single-currency workspace, which is every workspace that
has one denomination, the cancellation is exact in every currency, always.

### Security

`public.transfers` is owner-scoped, RLS-enabled and RLS-forced, with no delete policy at
all — financial history is voided, never removed. Both `from_person_id` and
`to_person_id` are **composite foreign keys** onto `people (owner_id, id)`, so a transfer
naming a person in another workspace is refused structurally rather than by a check
somebody could forget to write. It holds for every writer including the service role.

`db/tests/10_transfers.sql` asserts, as a second user, that another workspace can neither
read, retract nor edit a transfer of the first's, and that transferring to or from a
stranger's person is refused in both directions.

### What is refused

Same person, zero, negative, an unknown currency, a future date, and a person in another
workspace — all server-side, all with a sentence a user can act on. A repeated submission
carrying the same `client_token` returns the transfer the first one created rather than
moving the money twice; the unique index makes that hold even when two requests race.

---

## 3. PDF export

`GET /people/:id/statement` returns the account statement. Authorisation is the
database's, not the handler's: it calls `person_page()` as the signed-in user, which is
SECURITY INVOKER, so RLS confines it to that user's own workspace. There is no separate
check to forget to write.

**It computes no money.** Every figure comes from `lib/money.ts`, every label from
`lib/direction.ts` and `lib/transfers.ts`, every date from `lib/dates.ts`, and the running
balance is walked with `netDelta()` — the same function the person page's sparkline uses.
`lib/pdf/rows.ts` is the only place the statement decides what to say, and it takes its
formatter as an argument, so the tests run it with the *screen's* formatter and prove the
two produce the same strings.

The statement is set in Poppins, embedded and subsetted. That is not decoration: the
fourteen fonts every PDF reader has built in are WinAnsi-encoded and **have no rupee
sign**, so a rupee ledger exported in Helvetica prints a blank where the ₹ should be, or
refuses to encode the string at all. Poppins covers ₹, $, €, £, ¥, ₨, ₺, ₽, zł, Kč and
Devanagari. It does not cover ₪, ₫, ₩, ₦, ₱, ৳ or ฿ — `lib/pdf/typeface.ts` probes the
font's own character set and `lib/pdf/money.ts` drops the symbol for those, keeping the
unambiguous ISO code. The amount, its grouping and its decimals are never touched.

The two `.ttf` files are named in `next.config.ts` under `outputFileTracingIncludes`.
Nothing in the module graph imports them, so Next's file tracer cannot see they are
needed and would leave them out of a deployment bundle.

---

## 4. Tests

| Suite | What it covers |
|---|---|
| `db/tests/09_opening_balance_section.sql` | 29 assertions: reclassification in place, idempotence, separation from the timeline, still counted in the position, refusal to settle it through the generic path, its own dedicated settle path, the over-settlement ceiling, replacement history |
| `db/tests/10_transfers.sql` | 57 assertions: the headline case, workspace total unchanged, linked legs, every refusal, idempotency, cross-currency at the stored rate, frozen rates, manual rate and manual amount, one leg alone refused at commit, void, edit, the dashboard invariant, cross-workspace isolation |
| `web/src/lib/transfers.test.ts` | the label rules, and that they never fall back to credit/debit |
| `web/src/lib/pdf/statement.test.ts` | what a statement row and the opening block say |
| `web/src/lib/pdf/render.test.ts` | the export actually run: fonts embedded, glyphs present, pagination, reparse |
| `app/test/transfers_test.dart` | the Dart mirror of the label rules, and the transfer model |
| `app/test/opening_balance_section_test.dart` | the opening section, and the fallback against a pre-0019 database |
