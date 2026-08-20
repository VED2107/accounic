import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../widgets/amount_field.dart';
import 'sheet_scaffold.dart';

/// Settlement (context.md §9).
///
/// The direction is decided for the user whenever it can be — an account that
/// is only receivable can only be settled by money coming in — and offered as a
/// choice only when the person both owes and is owed.
///
/// Partial is the normal case, so the amount is freely editable with the
/// outstanding figure shown beside it. The database rejects anything above it,
/// so a stale screen cannot over-settle.
Future<bool> showSettleSheet(
  BuildContext context,
  WidgetRef ref, {
  required PersonBalance balance,
  required List<OpenTransaction> openTransactions,
  String? presetTransactionId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SettleSheet(
      balance: balance,
      openTransactions: openTransactions,
      presetTransactionId: presetTransactionId,
    ),
  );
  return result ?? false;
}

class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({
    required this.balance,
    required this.openTransactions,
    this.presetTransactionId,
  });

  final PersonBalance balance;
  final List<OpenTransaction> openTransactions;
  final String? presetTransactionId;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  late SettlementDirection _direction;
  late String? _transactionId = widget.presetTransactionId;
  final String _date = todayIso();
  final _note = TextEditingController();

  int? _amount;
  bool _saving = false;
  String? _error;

  bool get _canReceive => widget.balance.outstandingReceivable > 0;
  bool get _canPay => widget.balance.outstandingPayable > 0;
  bool get _bothSides => _canReceive && _canPay;

  @override
  void initState() {
    super.initState();
    final preset = widget.presetTransactionId == null
        ? null
        : widget.openTransactions
            .where((t) => t.id == widget.presetTransactionId)
            .firstOrNull;

    _direction = preset != null
        ? (preset.type == TxnType.credit
            ? SettlementDirection.moneyIn
            : SettlementDirection.moneyOut)
        : (_canReceive ? SettlementDirection.moneyIn : SettlementDirection.moneyOut);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  OpenTransaction? get _selected => _transactionId == null
      ? null
      : widget.openTransactions.where((t) => t.id == _transactionId).firstOrNull;

  List<OpenTransaction> get _matching => widget.openTransactions
      .where((t) => _direction == SettlementDirection.moneyIn
          ? t.type == TxnType.credit
          : t.type == TxnType.debit)
      .toList();

  int get _max =>
      _selected?.remainingMinor ??
      (_direction == SettlementDirection.moneyIn
          ? widget.balance.outstandingReceivable
          : widget.balance.outstandingPayable);

  Future<void> _save() async {
    if (_amount == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(ledgerRepositoryProvider).createSettlement(
            personId: widget.balance.personId,
            amountMinor: _amount!,
            date: _date,
            direction: _direction,
            transactionId: _transactionId,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.refreshLedger(personId: widget.balance.personId);
      if (mounted) Navigator.of(context).pop(true);
    } on Failure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final incoming = _direction == SettlementDirection.moneyIn;
    final accent = incoming ? context.money.receivable : context.money.payable;

    if (!_canReceive && !_canPay) {
      return SheetScaffold(
        title: 'Record a settlement',
        primaryLabel: 'Close',
        onPrimary: () => Navigator.of(context).pop(false),
        children: [
          Text(
            'Nothing is outstanding with ${widget.balance.name}.',
            style: TextStyle(color: context.money.inkMuted, height: 1.5),
          ),
        ],
      );
    }

    return SheetScaffold(
      title: 'Record a settlement',
      subtitle: incoming
          ? 'Money received from ${widget.balance.name}.'
          : 'Money paid to ${widget.balance.name}.',
      error: _error,
      busy: _saving,
      primaryColor: accent,
      primaryLabel: 'Record settlement',
      onPrimary: _amount == null ? null : _save,
      children: [
        if (_bothSides)
          Row(
            children: [
              Expanded(
                child: _SideOption(
                  selected: incoming,
                  title: 'I received',
                  amount: formatMinor(widget.balance.outstandingReceivable,
                      currency: currency),
                  color: context.money.receivable,
                  background: context.money.receivableSoft,
                  onTap: () => setState(() {
                    _direction = SettlementDirection.moneyIn;
                    _transactionId = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SideOption(
                  selected: !incoming,
                  title: 'I paid',
                  amount:
                      formatMinor(widget.balance.outstandingPayable, currency: currency),
                  color: context.money.payable,
                  background: context.money.payableSoft,
                  onTap: () => setState(() {
                    _direction = SettlementDirection.moneyOut;
                    _transactionId = null;
                  }),
                ),
              ),
            ],
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: incoming ? context.money.receivableSoft : context.money.payableSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incoming ? 'You will receive' : 'You will pay',
                  style: TextStyle(fontSize: 13, color: context.money.inkMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMinor(_max, currency: currency),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 18),

        if (_matching.isNotEmpty) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Against',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                value: _transactionId,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('The whole account'),
                  ),
                  for (final txn in _matching)
                    DropdownMenuItem<String?>(
                      value: txn.id,
                      child: Text(
                        '${friendlyDate(txn.transactionDate)} · '
                        '${formatMinor(txn.remainingMinor, currency: currency)} left'
                        '${txn.description == null ? '' : ' · ${txn.description}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _transactionId = value),
              ),
              const SizedBox(height: 4),
              Text(
                'Leave on the whole account to settle the oldest entries first.',
                style: TextStyle(fontSize: 12, color: context.money.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        AmountField(
          key: ValueKey('settle-$_direction-$_transactionId'),
          currency: currency,
          autofocus: true,
          maxMinor: _max,
          onChanged: (minor) => setState(() => _amount = minor),
        ),

        const SizedBox(height: 18),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Note', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _note,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: incoming ? 'Cash received' : 'Paid by UPI',
                counterText: '',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SideOption extends StatelessWidget {
  const _SideOption({
    required this.selected,
    required this.title,
    required this.amount,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String amount;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? background : context.colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : context.colors.outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? color : context.money.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
