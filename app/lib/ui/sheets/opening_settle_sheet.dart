import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/amount_field.dart';
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
  required String currency,
}) async {
  final result = await showAppSheet<bool>(
    context,
    (context) => _OpeningSettleSheet(
      person: person,
      opening: opening,
      currency: currency,
    ),
  );
  return result ?? false;
}

class _OpeningSettleSheet extends ConsumerStatefulWidget {
  const _OpeningSettleSheet({
    required this.person,
    required this.opening,
    required this.currency,
  });

  final Person person;
  final PersonOpening opening;
  final String currency;

  @override
  ConsumerState<_OpeningSettleSheet> createState() => _OpeningSettleSheetState();
}

class _OpeningSettleSheetState extends ConsumerState<_OpeningSettleSheet> {
  final String _date = todayIso();
  final _note = TextEditingController();

  late int? _amount = widget.opening.remainingMinor;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // No direction: settle_opening_balance() derives it from the opening
      // entry, so this client cannot record money coming in against a balance
      // the user owes.
      await ref.read(ledgerRepositoryProvider).settleOpeningBalance(
            personId: widget.person.id,
            amountMinor: _amount,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
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
    final incoming = opening.signedMinor > 0;

    return SheetScaffold(
      title: 'Settle the opening balance',
      subtitle: incoming
          ? 'Money received from $firstName against what the account opened with.'
          : 'Money paid to $firstName against what the account opened with.',
      error: _error,
      busy: _saving,
      primaryLabel: 'Record settlement',
      onPrimary: _amount == null ? null : _save,
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
                    formatMoney(opening.remainingMinor, currency: widget.currency),
                    style: context.moneyStyle(
                      MoneySize.large,
                      color: incoming ? palette.receivable : palette.payable,
                    ),
                  ),
                  if (opening.settledMinor > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${formatMoney(opening.settledMinor, currency: widget.currency)} already '
                      'settled of ${formatMoney(opening.amountMinor, currency: widget.currency)}',
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
          children: [
            // The opening balance is stored in the account's own denomination
            // and this settles that entry, so there is no currency to choose.
            AmountField(
              currency: widget.currency,
              initial: opening.remainingMinor,
              maxMinor: opening.remainingMinor,
              autofocus: true,
              onChanged: (minor) => setState(() => _amount = minor),
            ),
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
