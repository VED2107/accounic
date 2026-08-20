import type { TxnType } from '@/lib/types';

/**
 * Direction: the one place the product decides what credit and debit mean.
 *
 * See `docs/accounting-direction.md` for the full statement of the rule. The
 * short version, always from the owner's point of view:
 *
 *   PERSON → OWNER   the owner received money, so the owner now owes it back
 *                    = Credit = PAYABLE = red = "Money you owe"
 *
 *   OWNER → PERSON   the owner handed money over, so the person owes it back
 *                    = Debit  = RECEIVABLE = green = "Money owed to you"
 *
 * ---------------------------------------------------------------------------
 * A note on the stored values, because they read backwards and that is
 * deliberate rather than an oversight:
 *
 * `transactions.type` in the database is an enum whose labels were chosen under
 * the opposite vocabulary. The engine computes
 *
 *     outstanding_receivable = open rows of type 'credit'
 *     outstanding_payable    = open rows of type 'debit'
 *
 * so the stored label `'credit'` denotes the OWNER → PERSON direction — the
 * receivable one — and `'debit'` denotes PERSON → OWNER. Every balance, every
 * settlement pairing and every colour derived from those columns is already
 * correct under the rule above; only the two words were attached to the wrong
 * ends. So the fix is a vocabulary fix, not an arithmetic one, and no migration
 * is involved: flipping the engine would invert the meaning of every row already
 * recorded, which would be a data corruption rather than a correction.
 *
 * Nothing outside this module should compare a `TxnType` against a literal for
 * the purpose of labelling or colouring. Ask here instead.
 * ---------------------------------------------------------------------------
 */

/** The real-world movement of money, which is what the product actually means. */
export type Flow = 'person_to_owner' | 'owner_to_person';

export const FLOW_OF: Record<TxnType, Flow> = {
  credit: 'owner_to_person',
  debit: 'person_to_owner',
};

export const TYPE_FOR_FLOW: Record<Flow, TxnType> = {
  owner_to_person: 'credit',
  person_to_owner: 'debit',
};

/** What the user calls it. */
export function txnLabel(type: TxnType): 'Credit' | 'Debit' {
  return FLOW_OF[type] === 'person_to_owner' ? 'Credit' : 'Debit';
}

/** Plain English, the line that stops the two being mixed up (context.md §8). */
export function txnMeaning(type: TxnType): string {
  return FLOW_OF[type] === 'person_to_owner' ? 'They gave me money' : 'I gave them money';
}

/** What it does to the balance, in the user's words. */
export function txnEffect(type: TxnType): string {
  return FLOW_OF[type] === 'person_to_owner' ? 'I owe them' : 'They owe me';
}

/** True when this entry is money the owner will get back. */
export function isReceivable(type: TxnType): boolean {
  return FLOW_OF[type] === 'owner_to_person';
}

/** The tone every amount, icon and chip for this entry must use. */
export function txnTone(type: TxnType): 'receivable' | 'payable' {
  return isReceivable(type) ? 'receivable' : 'payable';
}

/**
 * The same question for an activity row, whose `entry_type` is a transaction
 * type on transactions and a settlement direction on settlements.
 */
export function entryIsReceivable(entryType: string): boolean {
  // 'in' is money arriving, which only ever settles a receivable.
  if (entryType === 'in') return true;
  if (entryType === 'out') return false;
  return isReceivable(entryType as TxnType);
}

/** Row heading for the activity timeline. */
export function entryLabel(entryKind: string, entryType: string): string {
  if (entryKind === 'settlement') {
    return entryType === 'in' ? 'Settlement received' : 'Settlement paid';
  }
  return txnLabel(entryType as TxnType);
}
