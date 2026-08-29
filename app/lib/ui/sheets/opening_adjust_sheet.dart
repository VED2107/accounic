import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/currencies.dart';
import '../../core/direction.dart';
import '../../core/failure.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/amount_field.dart';
import '../widgets/currency_field.dart';
import '../widgets/forms.dart';
import 'sheet_scaffold.dart';

/// Credit and debit against the opening balance (db/migrations/0022).
///
/// Deliberately NOT the transaction sheet. What this records is not a
/// transaction: it is a correction to the figure the account was carried in
/// with, and it must never appear among the regular transactions, never move
/// cash in hand, and never be counted twice on the dashboard. The database
/// enforces all four through `adjust_opening_balance()`, which is the only RPC
/// this sheet calls.
///
/// What it shares with the transaction sheet, and shares on purpose:
///
///   * the direction model. [MoneyFlow] is the single mapping between the words
///     Credit and Debit and the stored enum — the same one every other screen
///     goes through — so this cannot invent a direction of its own;
///   * the conversion path. The client sends what was typed, its currency and
///     the rate; the database does the arithmetic and freezes the rate on the
///     row. No converted figure is ever computed here, and a hand-typed rate is
///     stored exactly as a fetched one is.
Future<bool> showOpeningAdjustSheet(
  BuildContext context,
  WidgetRef ref, {
  required Person person,
  required PersonOpening opening,
  required String accountCurrency,
  required MoneyFlow flow,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (context) => _OpeningAdjustSheet(
      person: person,
      opening: opening,
      accountCurrency: accountCurrency,
      flow: flow,
    ),
  );
  return result ?? false;
}

class _OpeningAdjustSheet extends ConsumerStatefulWidget {
  const _OpeningAdjustSheet({
    required this.person,
    required this.opening,
    required this.accountCurrency,
    required this.flow,
  });

  final Person person;
  final PersonOpening opening;
  final String accountCurrency;
  final MoneyFlow flow;

  @override
  ConsumerState<_OpeningAdjustSheet> createState() => _OpeningAdjustSheetState();
}

class _OpeningAdjustSheetState extends ConsumerState<_OpeningAdjustSheet> {
  final String _date = todayIso();
  final _note = TextEditingController();

  int? _amount;
  bool _saving = false;
  String? _error;

  /// The currency being typed in. Opens on whatever the opening balance itself
  /// was stated in, so correcting a dirham opening balance starts in dirhams
  /// rather than making the user say so again.
  late String _entryCurrency = widget.opening.entryCurrency;

  bool _manual = false;
  int? _actual;
  bool _rateManual = false;
  int? _manualRateE9;

  String get _account => widget.accountCurrency;
  bool get _foreign => _entryCurrency != _account;

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
      final entry = _entryCurrency;

      final manualRate = foreign && _rateManual ? _manualRateE9 : null;
      final rate = foreign && manualRate == null
          ? await ref.read(ratesRepositoryProvider).rate(entry, _account)
          : null;
      final rateE9 = manualRate ?? rate?.rateE9;
      final rateSource = manualRate != null ? kManualRateSource : rate?.source;

      final manual = foreign && _manual && _actual != null;
      final mode = foreign ? (manual ? 'manual' : 'automatic') : null;

      if (foreign && rateE9 == null) {
        setState(() {
          _saving = false;
          _error = 'No $entry to $_account rate is available. Enter the amount in '
              '$_account instead — nothing has been saved.';
        });
        return;
      }

      await ref.read(ledgerRepositoryProvider).adjustOpeningBalance(
            personId: widget.person.id,
            // The words the user pressed, mapped onto the stored enum by the
            // one function that is allowed to do it.
            type: TxnType.forFlow(widget.flow),
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
    final opening = widget.opening;
    final firstName = widget.person.name.split(' ').first;
    final flow = widget.flow;

    return SheetScaffold(
      title: '${flow.label} the opening balance',
      subtitle: '${flow.meaning}. This corrects what the account opened with — '
          'it is not a transaction, and it will not appear among them.',
      error: _error,
      busy: _saving,
      primaryLabel: 'Record ${flow.label.toLowerCase()}',
      onPrimary: _canSave ? _save : null,
      children: [
        FormSection(
          first: true,
          title: 'Opening balance',
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
                    'What this account opened with',
                    style: TextStyle(fontSize: 13, color: palette.inkMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatMoney(
                      opening.entryAmountMinor,
                      currency: opening.entryCurrency,
                    ),
                    style: context.moneyStyle(
                      MoneySize.large,
                      color: opening.isReceivable ? palette.receivable : palette.payable,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    flow == MoneyFlow.ownerToPerson
                        ? 'A debit increases what $firstName owed you when the account opened.'
                        : 'A credit increases what you owed $firstName when the account opened.',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
        FormSection(
          title: 'Amount',
          aside: _foreign ? 'Account keeps $_account' : null,
          children: [
            AmountField(
              currency: _entryCurrency,
              autofocus: true,
              onChanged: (minor) => setState(() => _amount = minor),
            ),
            const SizedBox(height: AppSpacing.md),
            CurrencyField(
              label: 'Entered in',
              value: _entryCurrency,
              onChanged: (next) => setState(() => _entryCurrency = next),
              helper: _foreign
                  ? 'Converted into $_account when it is saved'
                  : 'This account is kept in $_account',
            ),
            if (_foreign) ...[
              const SizedBox(height: AppSpacing.md),
              ConversionPanel(
                amountMinor: _amount,
                from: _entryCurrency,
                to: _account,
                manual: _manual,
                onManualChanged: (manual) => setState(() => _manual = manual),
                onActualChanged: (minor) => setState(() => _actual = minor),
                rateManual: _rateManual,
                onRateManualChanged: (manual) => setState(() => _rateManual = manual),
                onManualRateChanged: (rateE9) => setState(() => _manualRateE9 = rateE9),
                // The opening balance's own rate is the sensible starting point
                // for a correction to it: same money, same day, same rate.
                initialRateE9: opening.exchangeRateE9,
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
              hint: 'Opening figure was short',
              maxLength: 500,
            ),
          ],
        ),
      ],
    );
  }
}
