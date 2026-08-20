# Direction: what credit and debit mean

This is the canonical statement of the rule. Both clients implement it and
neither is allowed to decide it locally:

- `web/src/lib/direction.ts`
- `app/lib/core/direction.dart`

Everything is stated from the **owner's** point of view — the person whose
workspace it is. There is no second perspective anywhere in the product.

## The rule

| Movement | Called | Balance | Colour | Reads as |
|---|---|---|---|---|
| **Person → owner** — they handed money over | **Credit** | **Payable** | red | "Money you owe" |
| **Owner → person** — the owner handed money over | **Debit** | **Receivable** | green | "Money owed to you" |

The reasoning, in one line each:

- Rahul gives Ved ₹5,000. Ved is holding Rahul's money, so **Ved owes Rahul**.
  It is a credit, and it is payable.
- Ved gives Rahul ₹5,000. Rahul is holding Ved's money, so **Rahul owes Ved**.
  It is a debit, and it is receivable.

Settlement is neutral in itself — no colour, no side. What it does is retire an
open amount on one side:

- money **arriving** can only close something the owner was owed → reduces
  **receivable**;
- money **paid out** can only close something the owner owed → reduces
  **payable**.

### Worked examples

| | Entry | Result |
|---|---|---|
| A | Person gives owner ₹1,000 | Credit ₹1,000 · Payable ₹1,000 · red |
| B | Owner gives person ₹1,000 | Debit ₹1,000 · Receivable ₹1,000 · green |
| C | A, then owner settles ₹2,000 of a ₹5,000 credit | Payable ₹3,000 · red |
| D | B, then person settles ₹2,000 of a ₹5,000 debit | Receivable ₹3,000 · green |

Net position is `receivable − payable`. Positive means the workspace is owed
money on balance; negative means it owes.

## The stored values read backwards, on purpose

`transactions.type` in the database is an enum whose two labels were chosen
under the opposite vocabulary, and the balance engine was built on them:

```sql
outstanding_receivable = total_credit - settled_in   -- rows of type 'credit'
outstanding_payable    = total_debit  - settled_out  -- rows of type 'debit'
net_balance            = outstanding_receivable - outstanding_payable
```

So in the database:

| Stored value | Direction | Side |
|---|---|---|
| `'credit'` | owner → person | receivable |
| `'debit'` | person → owner | payable |

which is the reverse of what the two words mean to the user.

**Only the words were wrong.** Every balance, every settlement pairing, every
total and every colour derived from those columns already matches the rule at the
top of this page. The correction is therefore a vocabulary correction made in the
presentation layer, and there is no migration:

- flipping the engine would invert the meaning of every row already recorded — a
  ₹5,000 receivable entered last month would silently become a ₹5,000 payable.
  That is data corruption, not a fix.
- the engine's arithmetic, its over-settlement guards and its RLS are verified by
  72 SQL assertions. Rewriting them to rename two columns buys nothing.

The cost is that a reader of the SQL sees `credit` and must remember it means the
receivable direction. That cost is paid once, here, and in the header comment of
each client's direction module. It is not paid again anywhere else in the code:
**nothing outside those two modules may compare a stored type against a literal
in order to label or colour something.**

## Checklist when touching this

- Labels come from `txnLabel` / `Flow.label`.
- Colours come from `txnTone` / `isReceivable` — never from the stored literal.
- Activity rows use `entryIsReceivable`, which also handles the `'in'` / `'out'`
  settlement directions.
- The engine's `credit` bucket in `activity_summary` is the **debit** column in
  the UI, and vice versa. The activity screen labels them accordingly.
- Flutter's `TxnType.forFlow(...)` is the only way to turn a user's choice into a
  stored value.

The Dart tests in `app/test/models_test.dart` (`group('direction ...')`) pin all
of this, including the deliberate inversion between the stored value and the
spoken word. If those tests ever need "fixing", read this page first.
