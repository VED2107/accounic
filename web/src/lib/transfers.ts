import type { TransferRole } from '@/lib/types';

/**
 * How a transfer is written on screen (upgrade §46, §47).
 *
 * One definition, used by the person timeline, the activity feed and the PDF
 * statement, so a transfer cannot be called one thing on a page and another in
 * an export. The Dart mirror is `app/lib/core/transfers.dart`.
 *
 * The row says where the money went, not what kind of ledger entry it is:
 *
 *     Transfer to Dhruv       ₹3,000 INR     on the source's timeline
 *     Transfer from Ved       ₹3,000 INR     on the destination's
 *
 * A leg is stored as an ordinary debit or credit, and the word "Debit" is
 * exactly the wrong label for it — the user did not lend Dhruv anything, they
 * moved their own money between two accounts.
 */
export function transferLabel(
  role: TransferRole | null | undefined,
  counterpartyName: string | null | undefined,
): string {
  const name = (counterpartyName ?? '').trim();
  if (role === 'source') return name ? `Transfer to ${name}` : 'Transfer out';
  if (role === 'destination') return name ? `Transfer from ${name}` : 'Transfer in';
  return 'Transfer';
}

/** True when a ledger row is one half of a transfer rather than an entry. */
export function isTransferEntry(row: {
  transfer_id?: string | null;
  entry_kind?: string;
}): boolean {
  return Boolean(row.transfer_id) && row.entry_kind !== 'settlement';
}

/**
 * Whether this side of a transfer increases the person's position.
 *
 * The destination receives, so its leg is a credit and the balance rises; the
 * source parts with it. Stated here rather than derived from the stored enum,
 * because the enum labels run the other way round to the spoken words — see
 * docs/accounting-direction.md and lib/direction.ts.
 */
export function transferIsIncoming(role: TransferRole | null | undefined): boolean {
  return role === 'destination';
}

/** `+` or `−` for a transfer leg, as the timeline and the statement print it. */
export function transferSign(role: TransferRole | null | undefined): string {
  return transferIsIncoming(role) ? '+' : '−';
}
