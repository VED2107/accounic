/// How a transfer is written on screen (upgrade 46, 47).
///
/// The Dart mirror of `web/src/lib/transfers.ts`, character for character in
/// what it produces. One definition per client, and a test on each side pins
/// them together, so a transfer cannot be called one thing on the web and
/// another in the app.
///
/// The row says where the money went, not what kind of ledger entry it is:
///
///     Transfer to Dhruv       ₹3,000 INR     on the source's timeline
///     Transfer from Ved       ₹3,000 INR     on the destination's
///
/// A leg is stored as an ordinary debit or credit, and the word "Debit" is
/// exactly the wrong label for it — the user did not lend Dhruv anything, they
/// moved their own money between two accounts.
library;

/// Which side of a transfer a ledger row is (db/migrations/0020).
enum TransferRole {
  source,
  destination;

  static TransferRole? parse(Object? value) => switch (value) {
        'source' => TransferRole.source,
        'destination' => TransferRole.destination,
        _ => null,
      };

  String get wire => name;
}

String transferLabel(TransferRole? role, String? counterpartyName) {
  final name = (counterpartyName ?? '').trim();
  return switch (role) {
    TransferRole.source => name.isEmpty ? 'Transfer out' : 'Transfer to $name',
    TransferRole.destination => name.isEmpty ? 'Transfer in' : 'Transfer from $name',
    null => 'Transfer',
  };
}

/// Whether this side of a transfer increases the person's position.
///
/// The destination receives, so its leg is a credit and the balance rises; the
/// source parts with it. Stated here rather than derived from the stored enum,
/// because the enum labels run the other way round to the spoken words — see
/// docs/accounting-direction.md and core/direction.dart.
bool transferIsIncoming(TransferRole? role) => role == TransferRole.destination;

/// `+` or `−` for a transfer leg, as the timeline and the statement print it.
String transferSign(TransferRole? role) => transferIsIncoming(role) ? '+' : '−';
