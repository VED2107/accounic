import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/amount_field.dart';
import '../widgets/currency_field.dart';
import '../widgets/forms.dart';
import '../../core/layout.dart';
import 'sheet_scaffold.dart';

/// Settling the opening balance — that entry, and nothing else (upgrade 48).
///
/// Deliberately not the settle sheet the regular transactions use. That one
/// asks which side is being settled and against which row; neither question
/// applies here. There is one opening balance, its direction is a property of
/// the entry, and the server derives it — so this asks for an amount and a note
/// and nothing else, and defaults the amount to closing it, which is the common
/// case.
Future<bool> showOpeningSettleSheet(
  BuildContext context,
  WidgetRef ref, {
  required Person person,
  required PersonOpening opening,
  required PositionSplit position,
  required String currency,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (context) => _OpeningSettleSheet(
      person: person,
      opening: opening,
      position: position,
      currency: currency,
    ),
  );
  return result ?? false;
}

class _OpeningSettleSheet extends ConsumerStatefulWidget {
  const _OpeningSettleSheet({
    required this.person,
    required this.opening,
    required this.position,
    required this.currency,
  });

  final Person person;
  final PersonOpening opening;

  /// What is left of the whole opening BOOK, not of the balance row alone
  /// (db/migrations/0022).
  ///
  /// The two differ the moment a credit or debit is recorded against the
  /// opening balance, and the difference is not cosmetic: `settle_opening_balance()`
  /// settles the book and refuses an amount larger than the book's remainder,
  /// so a sheet that offered the balance row's own remainder would default to a
  /// figure the server rejects.
  final PositionSplit position;
  final String currency;

  @override
  ConsumerState<_OpeningSettleSheet> createState() => _OpeningSettleSheetState();
}

class _OpeningSettleSheetState extends ConsumerState<_OpeningSettleSheet> {
  final String _date = todayIso();
  final _note = TextEditingController();

  /// What is actually left of the opening book, unsigned.
  int get _outstanding => widget.position.positionMinor.abs();

  late int? _amount = _outstanding;
  bool _saving = false;
  String? _error;

  /// The currency the payment is being TYPED in. An opening balance can be paid
  /// off in a currency the account is not kept in, exactly as an ordinary
  /// settlement can, and `settle_opening_balance()` has taken the conversion
  /// arguments since db/migrations/0021.
  String? _entryCurrency;

  /// The two overrides. One says what a unit is worth; the other says what
  /// actually arrived once a bank had taken its cut. Both are offered wherever
  /// an automatic conversion is.
  bool _manual = false;
  int? _actual;
  bool _rateManual = false;
  int? _manualRateE9;

  String get _entry => _entryCurrency ?? widget.currency;
  bool get _foreign => _entry != widget.currency;

  bool get _canSave =>
      _amount != null &&
      !_saving &&
      !(_manual && _foreign && _actual == null) &&
      !(_rateManual && _foreign && _manualRateE9 == null);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final foreign = _foreign;
      final entry = _entry;
      final account = widget.currency;

      final manualRate = foreign && _rateManual ? _manualRateE9 : null;
      final rate = foreign && manualRate == null
          ? await ref.read(ratesRepositoryProvider).rate(entry, account)
          : null;
      final rateE9 = manualRate ?? rate?.rateE9;
      final rateSource = manualRate != null ? kManualRateSource : rate?.source;

      final manual = foreign && _manual && _actual != null;
      final mode = foreign ? (manual ? 'manual' : 'automatic') : null;

      if (foreign && rateE9 == null) {
        setState(() {
          _saving = false;
          _error = 'No $entry to $account rate is available. Enter the amount in '
              '$account instead — nothing has been saved.';
        });
        return;
      }

      // No direction: settle_opening_balance() derives it from the opening
      // book's net position, so this client cannot record money coming in
      // against a balance the user owes.
      await ref.read(ledgerRepositoryProvider).settleOpeningBalance(
            personId: widget.person.id,
            amountMinor: foreign ? null : _amount,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            enteredAmountMinor: foreign ? _amount : null,
            enteredCurrency: foreign ? entry : null,
            exchangeRateE9: rateE9,
            rateSource: rateSource,
            convertedAmountMinor: manual ? _actual : null,
            conversionMode: mode,
          );
      ref.refreshLedger(personId: widget.person.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final firstName = widget.person.name.split(' ').first;
    // Which way money must move to retire the book, derived from the book's
    // net position exactly as the server derives it — not from the balance row,
    // which an adjustment can outweigh.
    final incoming = widget.position.positionMinor > 0;

    return SheetScaffold(
      title: 'Settle the opening balance',
      subtitle: incoming
          ? 'Money received from $firstName against what the account opened with.'
          : 'Money paid to $firstName against what the account opened with.',
      error: _error,
      busy: _saving,
      primaryLabel: 'Record settlement',
      onPrimary: _canSave ? _save : null,
      children: [
        FormSection(
          first: true,
          title: 'Outstanding',
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: palette.sunken,
                borderRadius: AppRadius.fieldAll,
                border: Border.all(color: palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Outstanding on the opening balance',
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(_outstanding, currency: widget.currency, base: widget.currency),
                    style: context.moneyStyle(
                      MoneySize.large,
                      color: incoming ? palette.receivable : palette.payable,
                    ),
                  ),
                  if (widget.position.settledMinor > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${formatMoney(widget.position.settledMinor, currency: widget.currency, base: widget.currency)} already '
                      'settled against the opening balance',
                      style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Amount',
          aside: _foreign ? 'Account keeps ${widget.currency}' : null,
          children: [
            AmountField(
              key: ValueKey('opening-settle-$_entry'),
              currency: _entry,
              initial: _foreign ? null : _outstanding,
              // The ceiling is an account-currency figure and can only be
              // applied to an amount typed in that currency. Typed in another,
              // the database's own guard is what enforces it.
              maxMinor: _foreign ? null : _outstanding,
              autofocus: true,
              onChanged: (minor) => setState(() => _amount = minor),
            ),
            const SizedBox(height: AppSpacing.md),
            CurrencyField(
              label: 'Paid in',
              value: _entry,
              onChanged: (next) => setState(() => _entryCurrency = next),
              helper: _foreign
                  ? 'Converted into ${widget.currency} when it is saved'
                  : 'This account is kept in ${widget.currency}',
            ),
            if (_foreign) ...[
              const SizedBox(height: AppSpacing.md),
              ConversionPanel(
                amountMinor: _amount,
                from: _entry,
                to: widget.currency,
                manual: _manual,
                onManualChanged: (manual) => setState(() => _manual = manual),
                onActualChanged: (minor) => setState(() => _actual = minor),
                rateManual: _rateManual,
                onRateManualChanged: (manual) => setState(() => _rateManual = manual),
                onManualRateChanged: (rateE9) => setState(() => _manualRateE9 = rateE9),
                // The opening balance's own rate is the sensible starting point
                // for a payment against it.
                initialRateE9: widget.opening.exchangeRateE9,
              ),
            ],
          ],
        ),
        FormSection(
          title: 'Details',
          children: [
            AppTextField(
              controller: _note,
              label: 'Note',
              hint: 'Cash received',
              maxLength: 500,
            ),
          ],
        ),
      ],
    );
  }
}
