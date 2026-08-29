library;

import '../data/models.dart';
import 'currencies.dart';
import 'dates.dart';
import 'direction.dart';
import 'money.dart';
import 'transfers.dart';

/// What a statement says, before anything is drawn.
///
/// The Dart twin of `web/src/lib/pdf/rows.ts`, and deliberately the same shape:
/// pure, testable without a PDF reader, and the ONLY place this client decides
/// what a statement says. Every string below comes from `core/money.dart`,
/// `core/direction.dart`, `core/transfers.dart` or `core/dates.dart` — the same
/// four modules the screens use.
///
/// ONE RULE GOVERNS THIS FILE, and it is the same rule `statement.ts` states:
/// **it computes no money.** Every figure is one the database returned, or a
/// string a formatter produced from one. The running balance is walked with
/// [netDelta] rather than with arithmetic invented here. A statement that
/// disagreed with the screen it was exported from would be worse than no
/// statement, and the only way to guarantee it cannot is to give it nothing of
/// its own to disagree with.

/// How one entry moves the net position.
///
/// A receivable transaction pushes the balance up, a payable one pulls it down;
/// a settlement moves it back towards zero from whichever side it closes.
/// Voided entries move nothing — that is what voiding is for. Identical to
/// `netDelta()` in `web/src/lib/series.ts`.
int netDelta(TimelineEntry entry) {
  if (entry.isVoid) return 0;
  if (!entry.isSettlement) {
    return (entry.txnType?.isReceivable ?? true)
        ? entry.amountMinor
        : -entry.amountMinor;
  }
  return entry.direction == SettlementDirection.moneyIn
      ? -entry.amountMinor
      : entry.amountMinor;
}

/// How a statement writes money.
///
/// Injected rather than imported for exactly one reason, and it is the same
/// reason `web/src/lib/pdf/rows.ts` injects it: the PDF has a constraint the
/// screen does not, because an embedded typeface may have no glyph for a
/// currency symbol. Injecting it means these row rules can be tested against
/// the plain screen formatter and still be the rules the PDF runs.
class StatementFormatter {
  const StatementFormatter({this.money = formatMoney, this.approx = formatApprox});

  /// `$40.00 USD` — an amount in the currency it was entered in.
  final String Function(int minor, {String? currency, bool compactDecimals}) money;

  /// `≈ ₹3,817.11 INR` — the same money converted, marked as a conversion.
  final String Function(int minor, {String? currency}) approx;
}

/// The screen's formatter: what every figure looks like in the app itself.
const kScreenFormatter = StatementFormatter();

/// One printable line of a statement.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.time,
    required this.type,
    required this.description,
    required this.original,
    required this.equivalent,
    required this.rate,
    required this.balance,
    required this.balanceReceivable,
    required this.isVoid,
    required this.isTransfer,
  });

  /// `28 Aug 2026`
  final String date;

  /// `08:42 PM`, or '' when the row carries no usable timestamp.
  final String time;

  /// `Credit`, `Debit`, `Transfer to Dhruv`, `Settlement received`.
  final String type;
  final String description;

  /// The amount as entered, in the currency it was entered in.
  final String original;

  /// The one equivalent worth printing, or null when there is none.
  final String? equivalent;

  /// The rate that links the two, or null when nothing was converted.
  final String? rate;

  /// The running position after this row, in the account currency.
  final String balance;
  final bool balanceReceivable;
  final bool isVoid;
  final bool isTransfer;
}

/// What a timeline entry is called — the same three cases the screen uses.
String rowType(TimelineEntry entry) {
  if (entry.isTransfer) {
    return transferLabel(entry.transferRole, entry.transferCounterpartyName);
  }
  if (entry.isOpening) {
    return entry.isOpeningAdjustment
        ? 'Opening ${MoneyFlow.parse(entry.txnType?.wire).label.toLowerCase()}'
        : 'Opening balance';
  }
  if (entry.isSettlement) {
    return entry.direction == SettlementDirection.moneyIn
        ? 'Settlement received'
        : 'Settlement paid';
  }
  return MoneyFlow.parse(entry.txnType?.wire).label;
}

/// The other party, or the note.
String rowDescription(TimelineEntry entry) {
  final note = (entry.note ?? '').trim();
  if (note.isNotEmpty) return note;
  final counterparty = entry.transferCounterpartyName;
  if (entry.isTransfer && counterparty != null && counterparty.isNotEmpty) {
    return counterparty;
  }
  return '—';
}

/// The one equivalent that says something the original figure does not.
///
/// The ledger figure when the entry was converted INTO this account, otherwise
/// the workspace-currency figure for an account kept in a foreign currency —
/// never both, and never the equivalent on its own. Identical to the rule the
/// person timeline applies, deliberately: a row that showed two figures on
/// screen and three in the export would be two different documents.
({int minor, String currency})? rowEquivalent({
  required int amountMinor,
  String? entryCurrency,
  String? baseCurrency,
  int? amountBaseMinor,
  required String currency,
  required String fallbackBaseCurrency,
}) {
  final entry = normaliseCode(entryCurrency).isEmpty ? currency : normaliseCode(entryCurrency);
  final base = normaliseCode(baseCurrency).isEmpty
      ? normaliseCode(fallbackBaseCurrency)
      : normaliseCode(baseCurrency);

  if (entry != currency) return (minor: amountMinor, currency: currency);
  if (base.isNotEmpty && base != currency && amountBaseMinor != null) {
    return (minor: amountBaseMinor, currency: base);
  }
  return null;
}

/// The rate line under a converted figure, or null when nothing was converted.
///
/// Printed at the precision that reproduces the figure above it, which is what
/// `formatRate` exists for: a rounded display rate that does not reconcile with
/// the amount beside it is the bug db/migrations/0018 was written to end.
String? rowRate(
  String? enteredCurrency,
  int? rateE9,
  int? enteredMinor,
  String accountCurrency,
) {
  if (enteredCurrency == null || rateE9 == null) return null;
  return rateSentence(enteredCurrency, accountCurrency, rateE9, amountMinor: enteredMinor);
}

/// The opening balance, resolved into the lines a statement prints.
class OpeningLines {
  const OpeningLines({
    required this.original,
    required this.equivalent,
    required this.rate,
    required this.dated,
    required this.recorded,
    required this.direction,
    required this.settlement,
    required this.outstanding,
  });

  final String original;
  final String? equivalent;
  final String? rate;
  final String dated;
  final String recorded;

  /// Whose favour it runs in, in words.
  final String direction;

  /// Where its own settlement stands, or null when nothing has been settled.
  final String? settlement;

  /// What is left of the whole opening book, in the account currency.
  final String outstanding;
}

OpeningLines openingLines(
  PersonOpening opening,
  PositionSplit position,
  String currency,
  String baseCurrency, {
  StatementFormatter format = kScreenFormatter,
}) {
  final equivalent = rowEquivalent(
    amountMinor: opening.amountMinor,
    entryCurrency: opening.entryCurrency,
    baseCurrency: opening.baseCurrency,
    amountBaseMinor: opening.amountBaseMinor,
    currency: currency,
    fallbackBaseCurrency: baseCurrency,
  );

  return OpeningLines(
    original: format.money(opening.entryAmountMinor, currency: opening.entryCurrency),
    equivalent: equivalent == null
        ? null
        : format.approx(equivalent.minor, currency: equivalent.currency),
    rate: rowRate(
      opening.enteredCurrency,
      opening.exchangeRateE9,
      opening.enteredAmountMinor,
      currency,
    ),
    dated: statementDate(opening.entryDate),
    recorded: '${statementDate(opening.createdAt)} at ${timeOfDay(opening.createdAt)}',
    direction: opening.signedMinor >= 0
        ? 'Owed to you when the account opened'
        : 'Owed by you when the account opened',
    settlement: opening.settledMinor == 0
        ? null
        : '${format.money(opening.settledMinor, currency: currency)} settled'
            '${opening.isOutstanding ? ' · ${format.money(opening.remainingMinor, currency: currency)} left' : ' · settled in full'}',
    outstanding: format.money(position.positionMinor.abs(), currency: currency),
  );
}

/// Every printable row of a list, oldest first, with a running balance.
///
/// [closingMinor] is the position these rows end on — the cash-in-hand position
/// for the regular transactions, the opening book's for the opening activity.
/// The running figure is walked FORWARD from `closingMinor` minus the effect of
/// every listed row, so the last row lands exactly on the figure printed at the
/// top of the section rather than on an independently accumulated
/// approximation.
List<StatementRow> buildStatementRows(
  List<TimelineEntry> entries, {
  required int closingMinor,
  required String currency,
  required String baseCurrency,
  StatementFormatter format = kScreenFormatter,
}) {
  // person_page() returns newest first; a statement reads oldest first.
  final ordered = [...entries]..sort((a, b) {
      if (a.entryDate != b.entryDate) return a.entryDate.compareTo(b.entryDate);
      return a.createdAt.compareTo(b.createdAt);
    });

  final total = ordered.fold<int>(0, (sum, entry) => sum + netDelta(entry));
  var running = closingMinor - total;

  return [
    for (final entry in ordered)
      () {
        running += netDelta(entry);

        final entryMinor = entry.entryAmountMinorOr(currency);
        final entryCurrency = entry.entryCurrencyOr(currency);
        final equivalent = rowEquivalent(
          amountMinor: entry.amountMinor,
          entryCurrency: entryCurrency,
          baseCurrency: entry.baseCurrency,
          amountBaseMinor: entry.amountBaseMinor,
          currency: currency,
          fallbackBaseCurrency: baseCurrency,
        );

        return StatementRow(
          date: statementDate(entry.entryDate),
          time: timeOfDay(entry.createdAt),
          type: rowType(entry),
          description: rowDescription(entry),
          original: format.money(entryMinor, currency: entryCurrency),
          equivalent: equivalent == null
              ? null
              : format.approx(equivalent.minor, currency: equivalent.currency),
          rate: rowRate(
            entry.enteredCurrency,
            entry.exchangeRateE9,
            entry.enteredAmountMinor,
            currency,
          ),
          balance: format.money(running.abs(), currency: currency),
          balanceReceivable: running >= 0,
          isVoid: entry.isVoid,
          isTransfer: entry.isTransfer,
        );
      }(),
  ];
}
