import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/amount_field.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../widgets/currency_field.dart';
import '../widgets/forms.dart';
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
  final result = await showAppSheet<bool>(
    context,
    (context) => _SettleSheet(
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

  /// The currency the payment is being TYPED in. Follows the account until the
  /// user says otherwise, because the ordinary case should cost no decisions.
  ///
  /// A settlement may legitimately be handed over in another currency — a
  /// dirham account paid off in rupees — and until now this sheet refused to
  /// hear it. `create_settlement()` has taken the conversion arguments since
  /// db/migrations/0011; only the client was not sending them.
  String? _entryCurrency;

  /// Whether the converted figure was replaced by what actually changed hands,
  /// and what that figure is, in the ACCOUNT currency.
  bool _manual = false;
  int? _actual;

  /// Whether the RATE is one the user typed rather than the fetched one, and
  /// that rate. Separate from the override above: one says what a unit is
  /// worth, the other says what actually arrived.
  bool _rateManual = false;
  int? _manualRateE9;

  /// What the typed amount comes to in the ACCOUNT's currency.
  ///
  /// Reported by the conversion panel, which owns the rate and both overrides.
  /// Null until there is an answer. Before v1.11.0 this sheet did its
  /// arithmetic on the typed figure alone — so settling a rupee account with
  /// AED 40 printed "Settling ₹40.00" and computed the remainder from it. The
  /// number was in the wrong currency and every figure derived from it was
  /// wrong with it. Same fix, same reason, as the web client's.
  int? _converted;

  String get _accountCurrency => widget.balance.currency;
  String get _entry => _entryCurrency ?? _accountCurrency;
  bool get _foreign => _entry != _accountCurrency;

  bool get _canSave =>
      _amount != null &&
      !_saving &&
      // An override with nothing valid typed into it is not savable: the ledger
      // figure would be missing, and falling back to the automatic one silently
      // would be the opposite of what the user asked for.
      !(_manual && _foreign && _actual == null) &&
      !(_rateManual && _foreign && _manualRateE9 == null);

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

  /// The settlement in the account's own currency — the only denomination the
  /// ceiling, the remainder and the ledger are expressed in.
  int? get _ledgerMinor => _foreign ? _converted : _amount;

  int get _settling => (_ledgerMinor ?? 0).clamp(0, _max);

  /// Over the ceiling is possible only on a foreign entry, where the field has
  /// no ceiling to clamp against because the figure is not known until it is
  /// converted. The database refuses it either way; saying so before the submit
  /// is kinder than saying so after.
  bool get _overCeiling => _ledgerMinor != null && _ledgerMinor! > _max;

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
      final account = _accountCurrency;

      // A hand-typed rate needs no lookup and must not be quietly replaced by
      // one: it is the rate for this settlement, stored on the row exactly as a
      // fetched one is.
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

      final result = await ref.read(ledgerRepositoryProvider).createSettlement(
            personId: widget.balance.personId,
            // Cross-currency: send what was typed and the rate, and let the
            // database derive the account figure. Never a number computed here.
            amountMinor: foreign ? null : _amount,
            date: _date,
            direction: _direction,
            transactionId: _transactionId,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            enteredAmountMinor: foreign ? _amount : null,
            enteredCurrency: foreign ? entry : null,
            exchangeRateE9: rateE9,
            rateSource: rateSource,
            convertedAmountMinor: manual ? _actual : null,
            conversionMode: mode,
          );

      // What actually landed in the account, which on a converted settlement is
      // not the figure the user typed. Read back from the row the database
      // wrote rather than re-derived here.
      final settled = result.amountMinor ?? _amount!;
      final remaining = (_max - settled).clamp(0, _max);
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
    // The ACCOUNT's currency, not the workspace's.
    //
    // This read `currencyProvider` — the workspace currency — so a settlement
    // against a dirham account opened offering "350 INR" for an outstanding
    // 350 AED. Every figure on this sheet is one of that account's own, and
    // `person_balances` denominates all of them in its ledger currency; the
    // workspace currency has no business here at all. The database was never
    // wrong (the amount is written in the account's denomination either way),
    // but the sheet was telling the user it was about to settle a different
    // sum of money.
    final currency = widget.balance.currency;
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
      onPrimary: _canSave ? _save : null,
      children: [
        FormSection(
          first: true,
          title: 'What is being settled',
          children: [
            if (_bothSides)
              Row(
                children: [
                  Expanded(
                    child: _SideOption(
                      selected: incoming,
                      title: 'I received',
                      amount: formatMoney(widget.balance.outstandingReceivable,
                          currency: currency),
                      color: context.money.receivable,
                      background: context.money.receivableSoft,
                      onTap: () => setState(() {
                        _direction = SettlementDirection.moneyIn;
                        _transactionId = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: _SideOption(
                      selected: !incoming,
                      title: 'I paid',
                      amount:
                          formatMoney(widget.balance.outstandingPayable, currency: currency, base: currency),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: incoming ? context.money.receivableSoft : context.money.payableSoft,
                  borderRadius: AppRadius.fieldAll,
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
                      formatMoney(_max, currency: currency, base: currency),
                      style: context.moneyStyle(MoneySize.large, color: accent),
                    ),
                  ],
                ),
              ),

            if (_matching.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Against',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: context.money.inkMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm - 2),
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
                            '${formatMoney(txn.remainingMinor, currency: currency, base: currency)} left'
                            '${txn.description == null ? '' : ' · ${txn.description}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _transactionId = value),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Leave on the whole account to settle the oldest entries first.',
                    style: TextStyle(fontSize: 12, color: context.money.inkFaint),
                  ),
                ],
              ),
            ],
          ],
        ),

        // The settlement, as a chain the reader can follow end to end
        // (v1.11.0). Four questions, in order, with no arithmetic asked of
        // anyone: what is owed → what I am paying → in what, at what rate →
        // and therefore what this settles.
        //
        // The three-cell strip that used to sit here printed the arithmetic
        // ABOVE the field it depended on, so opening the sheet read "Settling
        // 0.00, Remaining <the whole balance>" — an answer to a question nobody
        // had asked yet.
        FormSection(
          title: 'Settlement',
          aside: _foreign ? 'Account keeps $currency' : currency,
          children: [
            _BalanceDue(
              minor: _max,
              currency: currency,
              onEntry: _selected != null,
            ),
            const SizedBox(height: AppSpacing.md),
            AmountField(
              key: ValueKey('settle-$_direction-$_transactionId-$_entry'),
              currency: _entry,
              autofocus: true,
              // The ceiling is an ACCOUNT-currency figure, so it can only be
              // applied to an amount typed in that currency. Typed in another,
              // the over-settlement guard in the database is what enforces it —
              // clamping a rupee figure against a dirham ceiling would be
              // comparing two different quantities.
              maxMinor: _foreign ? null : _max,
              onChanged: (minor) => setState(() => _amount = minor),
            ),
            const SizedBox(height: AppSpacing.md),
            CurrencyField(
              label: 'Settlement currency',
              value: _entry,
              onChanged: (next) => setState(() => _entryCurrency = next),
              helper: _foreign
                  ? 'Converted into $currency when it is saved'
                  : 'This account is kept in $currency',
            ),
            if (_foreign) ...[
              const SizedBox(height: AppSpacing.md),
              // Both overrides, because both questions are real: the rate may be
              // wrong, and the amount that actually arrived may differ from what
              // any rate implies once a bank has taken its cut.
              ConversionPanel(
                amountMinor: _amount,
                from: _entry,
                to: currency,
                manual: _manual,
                onManualChanged: (manual) => setState(() => _manual = manual),
                onActualChanged: (minor) => setState(() => _actual = minor),
                rateManual: _rateManual,
                onRateManualChanged: (manual) => setState(() => _rateManual = manual),
                onManualRateChanged: (rateE9) => setState(() => _manualRateE9 = rateE9),
                onResolved: (minor) => setState(() => _converted = minor),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // The end of the chain. One figure, in the account's currency,
            // named for what it does to the reader's money — and under it, what
            // is left.
            _Outcome(
              settling: _settling,
              remaining: _max - _settling,
              currency: currency,
              incoming: incoming,
              accent: accent,
              overBy: _overCeiling ? _max : null,
            ),
          ],
        ),

        FormSection(
          title: 'Details',
          aside: 'Optional',
          children: [
            AppTextField(
              label: 'Note',
              controller: _note,
              icon: AppIcons.note,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              hint: incoming ? 'Cash received' : 'Paid by UPI',
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


/// What is owed, stated before anything is typed — the anchor the rest of the
/// sheet is measured against.
class _BalanceDue extends StatelessWidget {
  const _BalanceDue({
    required this.minor,
    required this.currency,
    required this.onEntry,
  });

  final int minor;
  final String currency;

  /// True when a single transaction was named rather than the whole account.
  final bool onEntry;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              onEntry ? 'Balance due on this entry' : 'Balance due',
              style: TextStyle(fontSize: 13, color: palette.inkMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatMoney(minor, currency: currency, base: currency),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.colors.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the settlement comes to, and what it leaves behind.
///
/// The figure here is always in the ACCOUNT's currency, whatever the payment
/// was typed in — that is the whole reason the conversion panel reports what it
/// resolves to instead of the sheet guessing from the typed number.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.settling,
    required this.remaining,
    required this.currency,
    required this.incoming,
    required this.accent,
    this.overBy,
  });

  final int settling;
  final int remaining;
  final String currency;
  final bool incoming;
  final Color accent;

  /// The ceiling, when the converted amount is above it. Null otherwise.
  final int? overBy;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final idle = settling == 0;
    final closes = remaining == 0 && settling > 0;

    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.enter,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: idle
            ? palette.sunken
            : incoming
                ? palette.receivableSoft
                : palette.payableSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: idle
              ? palette.line
              : incoming
                  ? palette.receivableLine
                  : palette.payableLine,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  incoming ? 'You’ll receive' : 'You’ll pay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AnimatedMoney(
                    settling,
                    currency: currency,
                    color: idle ? palette.inkFaint : accent,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: palette.line),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  closes ? 'Closes the balance' : 'Remaining after this',
                  style: TextStyle(fontSize: 12, color: palette.inkMuted),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AnimatedMoney(
                    remaining,
                    currency: currency,
                    color: closes ? context.colors.onSurface : palette.inkMuted,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          if (overBy != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'That comes to more than the '
              '${formatMoney(overBy!, currency: currency, base: currency)} '
              'outstanding. Reduce it, or settle the difference as a separate '
              'entry — the ledger will refuse an over-settlement.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.payable),
            ),
          ],
        ],
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
                '${formatMoney(amount, currency: currency, base: currency)} '
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
                          ? formatMoney(remaining, currency: currency, base: currency)
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
