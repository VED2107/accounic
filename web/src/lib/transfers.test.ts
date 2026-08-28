import { describe, expect, it } from 'vitest';
import {
  isTransferEntry,
  transferIsIncoming,
  transferLabel,
  transferSign,
} from '@/lib/transfers';
import { entryLabel } from '@/lib/direction';

/**
 * A transfer leg is stored as an ordinary debit or credit, and the whole point
 * of `lib/transfers.ts` is that it must not be *called* one. These tests pin
 * that, because the failure is silent: the balances would still be right and
 * every row would read as a loan that never happened.
 */
describe('transfer labels', () => {
  it('says where the money went, from either side', () => {
    expect(transferLabel('source', 'Dhruv')).toBe('Transfer to Dhruv');
    expect(transferLabel('destination', 'Ved')).toBe('Transfer from Ved');
  });

  it('still reads as a transfer when the other party is unknown', () => {
    // An archived or deleted counterparty must not produce "Transfer to null".
    expect(transferLabel('source', null)).toBe('Transfer out');
    expect(transferLabel('destination', undefined)).toBe('Transfer in');
    expect(transferLabel('source', '   ')).toBe('Transfer out');
    expect(transferLabel(null, 'Dhruv')).toBe('Transfer');
  });

  it('never falls back to the credit/debit vocabulary', () => {
    // The source leg is stored as a debit, which entryLabel would call "Credit"
    // under this product's direction rule. For a transfer that is simply the
    // wrong word — nobody lent anybody anything.
    expect(entryLabel('transaction', 'debit')).toBe('Credit');
    expect(transferLabel('source', 'Dhruv')).not.toContain('Credit');
    expect(transferLabel('destination', 'Ved')).not.toContain('Debit');
  });
});

describe('transfer direction', () => {
  it('credits the destination and debits the source', () => {
    expect(transferIsIncoming('destination')).toBe(true);
    expect(transferIsIncoming('source')).toBe(false);
    expect(transferSign('destination')).toBe('+');
    expect(transferSign('source')).toBe('−');
  });

  it('recognises a leg by its transfer id, and a settlement never is one', () => {
    expect(isTransferEntry({ transfer_id: 'abc', entry_kind: 'transaction' })).toBe(true);
    expect(isTransferEntry({ transfer_id: null, entry_kind: 'transaction' })).toBe(false);
    expect(isTransferEntry({ transfer_id: 'abc', entry_kind: 'settlement' })).toBe(false);
  });
});
