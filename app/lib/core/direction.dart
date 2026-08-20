library;

/// Direction: the one place this client decides what credit and debit mean.
///
/// The rule is stated in full in `docs/accounting-direction.md` and is
/// implemented identically in `web/src/lib/direction.ts`. Always from the
/// owner's point of view:
///
///   PERSON → OWNER   the owner received money, so the owner now owes it back
///                    = Credit = PAYABLE = red = "Money you owe"
///
///   OWNER → PERSON   the owner handed money over, so the person owes it back
///                    = Debit  = RECEIVABLE = green = "Money owed to you"
///
/// ---------------------------------------------------------------------------
/// The stored enum labels read backwards, and that is deliberate.
///
/// `transactions.type` in the database was named under the opposite vocabulary.
/// The engine computes
///
///     outstanding_receivable = open rows of type 'credit'
///     outstanding_payable    = open rows of type 'debit'
///
/// so the wire value `'credit'` denotes the OWNER → PERSON direction — the
/// receivable one — and `'debit'` denotes PERSON → OWNER. Every balance,
/// settlement pairing and colour derived from those columns is already correct
/// under the rule above; only the two words were attached to the wrong ends.
/// The fix is therefore a vocabulary fix, not an arithmetic one, and no
/// migration is involved: flipping the engine would invert the meaning of every
/// row already recorded.
///
/// Nothing outside this file and `models.dart` should compare a wire value
/// against a literal in order to label or colour something.
/// ---------------------------------------------------------------------------

/// The real-world movement of money, which is what the product actually means.
enum MoneyFlow {
  /// They gave the owner money. The owner owes it back — payable.
  personToOwner,

  /// The owner gave them money. They owe it back — receivable.
  ownerToPerson;

  String get label => this == MoneyFlow.personToOwner ? 'Credit' : 'Debit';

  /// Plain language, not accounting language (context.md §8).
  String get meaning =>
      this == MoneyFlow.personToOwner ? 'They gave me money' : 'I gave them money';

  /// What it does to the balance, in the user's words.
  String get effect => this == MoneyFlow.personToOwner ? 'I owe them' : 'They owe me';

  bool get isReceivable => this == MoneyFlow.ownerToPerson;

  /// The value the database stores for this direction.
  String get wire => this == MoneyFlow.personToOwner ? 'debit' : 'credit';

  static MoneyFlow parse(Object? wireValue) =>
      wireValue == 'debit' ? MoneyFlow.personToOwner : MoneyFlow.ownerToPerson;
}

/// The same question for an activity entry, whose type is a transaction type on
/// transactions and a settlement direction on settlements.
bool entryIsReceivable(String? entryType) {
  // 'in' is money arriving, which only ever retires a receivable.
  if (entryType == 'in') return true;
  if (entryType == 'out') return false;
  return MoneyFlow.parse(entryType).isReceivable;
}
