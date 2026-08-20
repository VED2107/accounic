import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/amount_field.dart';
import 'sheet_scaffold.dart';

/// Settlement (context.md §9).
///
/// The direction is decided for the user whenever it can be — an account that
/// is only receivable can only be settled by money coming in — and offered as a
/// choice only when the person both owes and is owed.
///
/// Partial is the normal case, so the amount is freely editable, the quarter
/// steps make the common cases one tap, and the arithmetic the user would
/// otherwise do in their head — outstanding, settling, what is left — is done
/// live above the field. The database still rejects anything above the ceiling,
/// so a stale screen cannot over-settle.
///
/// Closing a debt is the most satisfying thing this product does, so it is the
/// one place given a real success state rather than a dismissal and a snackbar.
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

  /// Set once the settlement is committed. The figures are captured at that
  /// moment rather than read back from the balance, which the refresh has
  /// already moved.
  ({int amount, int remaining})? _done;

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
      final settled = _amount!;
      final remaining = _max - settled;
      ref.refreshLedger(personId: widget.balance.personId);
      if (mounted) {
        setState(() {
          _saving = false;
          _done = (amount: settled, remaining: remaining);
        });
      }
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

    if (_done != null) {
      return _SettlementSuccess(
        amount: _done!.amount,
        remaining: _done!.remaining,
        incoming: incoming,
        currency: currency,
        name: widget.balance.name,
      );
    }

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
      primaryLabel: 'Settle now',
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

        _Arithmetic(
          outstanding: _max,
          settling: (_amount ?? 0).clamp(0, _max),
          currency: currency,
          accent: accent,
        ),

        const SizedBox(height: 18),

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


/// Outstanding, settling, remaining — the sum the user would otherwise do in
/// their head, kept live as they type.
class _Arithmetic extends StatelessWidget {
  const _Arithmetic({
    required this.outstanding,
    required this.settling,
    required this.currency,
    required this.accent,
  });

  final int outstanding;
  final int settling;
  final String currency;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final remaining = outstanding - settling;

    Widget cell(String label, int minor, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: palette.inkMuted)),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedMoney(
                    minor,
                    currency: currency,
                    color: color,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: palette.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell('Outstanding', outstanding, context.colors.onSurface),
            VerticalDivider(width: 1, color: palette.line),
            cell('Settling', settling, accent),
            VerticalDivider(width: 1, color: palette.line),
            cell('Remaining', remaining,
                remaining == 0 ? palette.inkFaint : context.colors.onSurface),
          ],
        ),
      ),
    );
  }
}

/// What a closed debt looks like. The tick draws itself once, the figures are
/// the ones from the moment of submission, and the balance on the screen behind
/// has already animated to its new value.
class _SettlementSuccess extends StatelessWidget {
  const _SettlementSuccess({
    required this.amount,
    required this.remaining,
    required this.incoming,
    required this.currency,
    required this.name,
  });

  final int amount;
  final int remaining;
  final bool incoming;
  final String currency;
  final String name;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SheetScaffold(
      title: 'Settled',
      primaryLabel: 'Done',
      onPrimary: () => Navigator.of(context).pop(true),
      children: [
        Center(
          child: Column(
            children: [
              const SettledMark(),
              const SizedBox(height: 16),
              Text('Settlement recorded', style: context.display(18)),
              const SizedBox(height: 6),
              Text(
                '${incoming ? 'Received' : 'Paid'} '
                '${formatMinor(amount, currency: currency)} '
                '${incoming ? 'from' : 'to'} $name',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: palette.inkMuted),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.sunken,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  border: Border.all(color: palette.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining > 0 ? 'Remaining balance' : 'Balance',
                      style: TextStyle(fontSize: 12, color: palette.inkMuted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remaining > 0
                          ? formatMinor(remaining, currency: currency)
                          : 'Fully settled',
                      style: context.display(22).copyWith(
                            color: remaining > 0
                                ? (incoming ? palette.receivable : palette.payable)
                                : context.colors.onSurface,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
