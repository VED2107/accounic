import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/direction.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../core/failure.dart';
import '../motion.dart';
import '../sheets/opening_adjust_sheet.dart';
import '../sheets/opening_settle_sheet.dart';
import '../sheets/person_sheet.dart';
import '../sheets/sheet_scaffold.dart';
import 'app_page.dart';
import 'common.dart';
import 'currency_field.dart';

/// The opening balance, in its own section (upgrade 46).
///
/// It used to sit in the timeline wearing a Credit or Debit label and offering
/// a Settle button, which said three untrue things at once: that it happened on
/// a particular day, that it was an ordinary entry, and that somebody could pay
/// it off on its own. It is none of those. It is what the account was carried
/// in with — so it gets a section, the two actions that actually apply to it
/// (change it, clear it), and no others.
///
/// What has not changed: it still counts towards the current position, in full.
/// The card says so, because a figure shown apart from the balance invites the
/// question of whether it is in the balance.
class OpeningBalanceCard extends ConsumerStatefulWidget {
  const OpeningBalanceCard({super.key, required this.page});

  final PersonPage page;

  @override
  ConsumerState<OpeningBalanceCard> createState() => _OpeningBalanceCardState();
}

class _OpeningBalanceCardState extends ConsumerState<OpeningBalanceCard> {
  bool _busy = false;

  PersonOpening? get _opening => widget.page.opening;
  String get _currency => widget.page.currency;
  int get _openingMinor => widget.page.balance.openingMinor;

  Future<void> _edit() async {
    final saved = await showPersonSheet(
      context,
      ref,
      person: widget.page.person,
      // The form reopens on the balance this account actually carries, so an
      // edit corrects the figure rather than starting from nothing.
      openingMinor: _openingMinor,
    );
    if (saved != null && mounted) showMessage(context, 'Account updated.');
  }

  /// Credit or debit against the opening balance (db/migrations/0022).
  ///
  /// The words go through [MoneyFlow] and nowhere else, exactly as they do on
  /// the transaction sheet, so this screen cannot mean something different by
  /// "Credit" than the rest of the app does.
  Future<void> _adjust(MoneyFlow flow) async {
    final opening = _opening;
    if (opening == null) return;

    final saved = await showOpeningAdjustSheet(
      context,
      ref,
      person: widget.page.person,
      opening: opening,
      accountCurrency: _currency,
      flow: flow,
    );
    if (saved && mounted) {
      showMessage(context, '${flow.label} recorded against the opening balance.');
    }
  }

  Future<void> _settle() async {
    final opening = _opening;
    if (opening == null) return;

    final saved = await showOpeningSettleSheet(
      context,
      ref,
      person: widget.page.person,
      opening: opening,
      // The BOOK's remainder, which is what the server settles.
      position: widget.page.openingPosition,
      currency: _currency,
    );
    if (saved && mounted) showMessage(context, 'Opening balance settled.');
  }

  Future<void> _clear() async {
    final ok = await confirm(
      context,
      icon: AppIcons.delete,
      title: 'Remove this opening balance?',
      confirmLabel: 'Remove',
      body: 'The current position drops by '
          '${formatMoney(_openingMinor.abs(), currency: _currency)}, because the account '
          'no longer starts anywhere but zero. Nothing is deleted — the entry is '
          'retracted and keeps its amount, currency, rate and date.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      // The same RPC the edit form uses, with the direction that means "there
      // isn't one". The database retracts the existing row rather than deleting
      // it, so the correction stays visible in the history below.
      await ref.read(ledgerRepositoryProvider).setOpeningBalance(
            personId: widget.page.person.id,
            direction: OpeningDirection.none,
          );
      Haptics.success();
      ref.refreshLedger(personId: widget.page.person.id);
    } on Failure catch (failure) {
      if (mounted) showMessage(context, failure.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final opening = _opening;
    final history = widget.page.openingHistory;
    final activity = widget.page.openingActivity;
    final position = widget.page.openingPosition;
    final firstName = widget.page.person.name.split(' ').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Opening balance'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (opening == null)
                Padding(
                  padding: context.cardPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No opening balance. This account started at zero.',
                          style: TextStyle(fontSize: 13.5, color: palette.inkMuted),
                        ),
                      ),
                      _OpeningAction(label: 'Add one', onTap: _busy ? null : _edit),
                    ],
                  ),
                )
              else
                Padding(
                  padding: context.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // The original figure leads, in the currency it
                                // was stated in. A dirham opening balance is
                                // 400 AED and says so — the rupee equivalent is
                                // a second line, never a replacement.
                                Text(
                                  formatMoney(
                                    opening.entryAmountMinor,
                                    currency: opening.entryCurrency,
                                  ),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: _openingMinor > 0
                                        ? palette.receivable
                                        : _openingMinor < 0
                                            ? palette.payable
                                            : context.colors.onSurface,
                                  ),
                                ),
                                if (_equivalent(opening) case final equivalent?) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    formatApprox(
                                      equivalent.minor,
                                      currency: equivalent.currency,
                                    ),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: palette.inkFaint,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.sm - 2),
                                Text(
                                  _openingMinor > 0
                                      ? '$firstName owed you this when the account opened'
                                      : 'You owed $firstName this when the account opened',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: palette.inkMuted,
                                  ),
                                ),
                                // Its own settlement, stated in its own section
                                // rather than left to be inferred from the
                                // account total.
                                if (opening.settledMinor > 0) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      StatusChip(
                                        opening.isOutstanding ? 'Part settled' : 'Settled',
                                        tone: opening.isOutstanding
                                            ? StatusTone.partial
                                            : StatusTone.done,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Flexible(
                                        child: Text(
                                          '${formatMoney(opening.settledMinor, currency: _currency)} settled'
                                          '${opening.isOutstanding ? ' · ${formatMoney(opening.remainingMinor, currency: _currency)} left' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: palette.inkFaint,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (opening.enteredCurrency != null &&
                                    opening.exchangeRateE9 != null) ...[
                                  const SizedBox(height: 2),
                                  RateNote(
                                    enteredMinor: opening.enteredAmountMinor,
                                    enteredCurrency: opening.enteredCurrency,
                                    rateE9: opening.exchangeRateE9,
                                    rateSource: opening.exchangeRateSource,
                                    accountCurrency: _currency,
                                    conversionMode: opening.conversionMode,
                                    autoConvertedMinor: opening.autoConvertedAmountMinor,
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  'Dated ${fullDate(opening.entryDate)}',
                                  style: TextStyle(fontSize: 12, color: palette.inkFaint),
                                ),
                              ],
                            ),
                          ),
                          // The three things that actually apply to an opening
                          // balance. Settling it is its OWN action, separate
                          // from the row action the regular transactions use —
                          // two sections, two settlement paths, one screen. The
                          // database enforces that separation: a settlement may
                          // name an opening balance only through this.
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            alignment: WrapAlignment.end,
                            children: [
                              // Credit and Debit against the opening balance
                              // itself. They are not the transaction actions
                              // wearing different labels: they call a different
                              // RPC, write into the opening book, and never
                              // reach the transactions below.
                              _OpeningAction(
                                label: MoneyFlow.personToOwner.label,
                                tone: palette.payable,
                                onTap: _busy ? null : () => _adjust(MoneyFlow.personToOwner),
                              ),
                              _OpeningAction(
                                label: MoneyFlow.ownerToPerson.label,
                                tone: palette.receivable,
                                onTap: _busy ? null : () => _adjust(MoneyFlow.ownerToPerson),
                              ),
                              if (position.positionMinor != 0)
                                _OpeningAction(
                                  label: 'Settle',
                                  tone: context.colors.primary,
                                  onTap: _busy ? null : _settle,
                                ),
                              _OpeningAction(label: 'Edit', onTap: _busy ? null : _edit),
                              _OpeningAction(
                                label: 'Remove',
                                tone: palette.payable,
                                onTap: _busy ? null : _clear,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Divider(height: 1, color: palette.line),
                      const SizedBox(height: AppSpacing.md),
                      // What is LEFT of the opening book, which is the figure
                      // the dashboard's "Opening balance" total is built from.
                      // Stated here so the two screens visibly agree.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Outstanding',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: palette.inkMuted,
                              ),
                            ),
                          ),
                          Text(
                            formatMoney(
                              position.positionMinor.abs(),
                              currency: _currency,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: position.positionMinor > 0
                                  ? palette.receivable
                                  : position.positionMinor < 0
                                      ? palette.payable
                                      : palette.inkFaint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Kept apart from cash in hand. The account position above is the '
                        'two added together, and neither screen ever counts this figure '
                        'twice.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: palette.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              // The opening book's own history: credits, debits and its own
              // settlements. These are deliberately absent from the regular
              // transactions below — that is the whole point of the section.
              if (activity.isNotEmpty)
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: palette.sunken,
                    border: Border(top: BorderSide(color: palette.line)),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: context.cardPadding.horizontal / 2,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OPENING BALANCE ACTIVITY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: palette.inkFaint,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final row in activity)
                        _OpeningActivityRow(row: row, accountCurrency: _currency),
                    ],
                  ),
                ),
              if (history.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: palette.sunken,
                  padding: EdgeInsets.symmetric(
                    horizontal: context.cardPadding.horizontal / 2,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REPLACED',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: palette.inkFaint,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm - 2),
                      for (final row in history)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${formatMoney(row.entryAmountMinor, currency: row.entryCurrency)}'
                            '  ·  retracted  ·  dated ${fullDate(row.entryDate)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: palette.inkFaint,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm - 2),
                      Text(
                        'Replacing an opening balance retracts the previous one rather '
                        'than editing it, so the correction stays visible. These affect '
                        'no balance.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: palette.inkFaint,
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

  /// The one equivalent worth printing under the original figure.
  ///
  /// The ledger figure when the opening balance was converted into this
  /// account, otherwise the workspace figure for an account kept in a foreign
  /// currency — never both, and never the equivalent alone. The same rule the
  /// timeline rows follow, so the two sections of the screen read identically.
  ({int minor, String currency})? _equivalent(PersonOpening opening) {
    if (opening.entryCurrency != _currency) {
      return (minor: opening.amountMinor, currency: _currency);
    }
    final base = opening.baseCurrency;
    final baseMinor = opening.amountBaseMinor;
    if (base != _currency && baseMinor != null) {
      return (minor: baseMinor, currency: base);
    }
    return null;
  }
}

/// One row of the opening book's history.
///
/// Reads exactly like a timeline row and is deliberately not one: it lives in
/// this section, and the regular transactions never contain it.
class _OpeningActivityRow extends StatelessWidget {
  const _OpeningActivityRow({required this.row, required this.accountCurrency});

  final TimelineEntry row;
  final String accountCurrency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final receivable = row.isSettlement
        ? row.direction == SettlementDirection.moneyIn
        : (row.txnType?.isReceivable ?? true);

    final label = row.isSettlement
        ? 'Settled'
        : MoneyFlow.parse(row.txnType?.wire).label;

    final sign = row.isSettlement ? '' : (receivable ? '+' : '−');
    final amount = formatMoney(
      row.entryAmountMinorOr(accountCurrency),
      currency: row.entryCurrencyOr(accountCurrency),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.inkMuted,
                  ),
                ),
                Text(
                  row.note?.isNotEmpty == true
                      ? '${fullDate(row.entryDate)} · ${row.note}'
                      : fullDate(row.entryDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: palette.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$sign$amount',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: row.isSettlement
                  ? palette.inkMuted
                  : (receivable ? palette.receivable : palette.payable),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpeningAction extends StatelessWidget {
  const _OpeningAction({required this.label, required this.onTap, this.tone});

  final String label;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final color = tone ?? context.colors.onSurface;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? palette.raised : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: hovered ? palette.lineStrong : palette.line),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ),
    );
  }
}
