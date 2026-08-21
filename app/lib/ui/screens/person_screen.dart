import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/direction.dart';
import '../../core/failure.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../sheets/person_sheet.dart';
import '../sheets/settle_sheet.dart';
import '../sheets/sheet_scaffold.dart';
import '../sheets/transaction_sheet.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';

/// Person / business account — the screen the product is really about
/// (context.md §6, §16).
///
/// Credit and debit appear together, never in separate modules, and the net
/// position is the largest thing on the page so "where do we stand?" needs no
/// arithmetic from the reader. The account is a statement, not a set of tabs.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(personPageProvider(personId));
    final currency = ref.watch(currencyProvider);
    final page = async.valueOrNull;

    return AppPage(
      title: page?.person.name ?? 'Account',
      subtitle: page == null ? null : _subtitle(page.person),
      width: ContentWidth.standard,
      bottomPadding: context.isCompact ? 48 : 48,
      leading: _BackButton(),
      actions: [
        if (page != null) PersonMenu(page: page),
      ],
      onRefresh: () async => ref.refresh(personPageProvider(personId).future),
      children: switch (async) {
        AsyncError(:final error) => [
            ErrorNote.forError(
              error,
              onRetry: () => ref.invalidate(personPageProvider(personId)),
            ),
          ],
        AsyncData(:final value) => _body(context, value, currency),
        _ => const [_PersonSkeleton()],
      },
    );
  }

  static String _subtitle(Person person) => [
        person.type.label,
        if (person.phone != null) person.phone!,
        if (person.isArchived) 'Archived',
      ].join(' · ');

  List<Widget> _body(BuildContext context, PersonPage page, String currency) {
    final groups = groupByDate(page.timeline, (entry) => entry.entryDate);

    return [
      // On a phone the app bar has only room for the name, so the identity row
      // is repeated here where the avatar and the metadata actually fit.
      if (context.isCompact) ...[
        Reveal(child: _Identity(person: page.person)),
        const SizedBox(height: AppSpacing.lg),
      ],

      Reveal(
        delay: const Duration(milliseconds: 30),
        child: _PositionCard(page: page, currency: currency),
      ),

      if (page.person.notes != null) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 70),
          child: Card(
            child: Padding(
              padding: context.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.note, size: AppIconSize.sm, color: context.money.inkFaint),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      page.person.notes!,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: context.money.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.xxl),

      if (page.timeline.isEmpty)
        const Card(
          child: EmptyState(
            icon: AppIcons.quiet,
            title: 'Nothing recorded yet',
            description: 'Your activity with this account will appear here.',
          ),
        )
      else
        for (final (index, group) in groups.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xl),
          Reveal(
            delay: Motion.stagger(index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  group.label,
                  trailing: '${group.items.length} '
                      '${group.items.length == 1 ? 'entry' : 'entries'}',
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (row, entry) in group.items.indexed)
                        TimelineTile(
                          entry: entry,
                          page: page,
                          currency: currency,
                          divider: row < group.items.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
    ];
  }
}

/// A back affordance that matches the header's other controls.
class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppIconAction(
      icon: AppIcons.back,
      tooltip: 'Back',
      onPressed: () =>
          Navigator.of(context).canPop() ? context.pop() : context.go('/people'),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Opacity(
          opacity: person.isArchived ? 0.6 : 1,
          child: Avatar(person.name, size: 48),
        ),
        const SizedBox(width: AppSpacing.md + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.display(20),
              ),
              const SizedBox(height: 2),
              Text(
                PersonScreen._subtitle(person),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.money.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Where we stand, what to do about it, and the four figures it is made of.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.page, required this.currency});

  final PersonPage page;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final balance = page.balance;
    final tone = balanceTone(balance.netBalance);
    final first = page.person.name.split(' ').first;

    final color = switch (tone) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => context.colors.onSurface,
    };

    return SectionCard(
      raised: true,
      brandRule: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(context.isCompact ? AppSpacing.lg : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.net, size: AppIconSize.xs, color: palette.inkFaint),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      'CURRENT POSITION',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm + 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  // Animates when it changes — which is exactly when a
                  // settlement has just been recorded on this screen.
                  child: AnimatedMoney(
                    balance.netBalance.abs(),
                    currency: currency,
                    color: color,
                    style: context.display(context.isCompact ? 34 : 40),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm - 1),
                Row(
                  children: [
                    Icon(
                      switch (tone) {
                        BalanceTone.receivable => AppIcons.receivable,
                        BalanceTone.payable => AppIcons.payable,
                        BalanceTone.settled => AppIcons.success,
                      },
                      size: AppIconSize.xs,
                      color: tone == BalanceTone.settled ? palette.inkFaint : color,
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Text(
                      switch (tone) {
                        BalanceTone.receivable => '$first owes you',
                        BalanceTone.payable => 'You owe $first',
                        BalanceTone.settled => 'Everything is settled',
                      },
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tone == BalanceTone.settled ? palette.inkFaint : color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg + 2),
                _ActionRow(page: page),
              ],
            ),
          ),
          Divider(height: 1, color: palette.line),
          _Figures(balance: balance, currency: currency, tone: tone),
        ],
      ),
    );
  }
}

/// Settle, credit, debit.
///
/// Settle is the filled one whenever anything is outstanding — that is the
/// spec's headline interaction. Credit and debit are separate buttons rather
/// than one "add" that then asks which: the type is the decision, so it is the
/// click.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.page});

  final PersonPage page;

  Future<void> _add(BuildContext context, WidgetRef ref, MoneyFlow flow) async {
    final saved = await showTransactionSheet(
      context,
      ref,
      person: PersonRef(page.person.id, page.person.name),
      defaultType: TxnType.forFlow(flow),
    );
    if (saved && context.mounted) showMessage(context, 'Transaction recorded.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = page.balance;
    final palette = context.money;

    return Row(
      children: [
        if (balance.hasOutstanding) ...[
          Expanded(
            child: _Action(
              label: 'Settle',
              icon: AppIcons.settlement,
              filled: true,
              onTap: () async {
                final saved = await showSettleSheet(
                  context,
                  ref,
                  balance: balance,
                  openTransactions: page.openTransactions,
                );
                if (saved && context.mounted) {
                  showMessage(context, 'Settlement recorded.');
                }
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
        ],
        Expanded(
          child: _Action(
            label: 'Credit',
            icon: AppIcons.payable,
            tint: palette.payable,
            onTap: () => _add(context, ref, MoneyFlow.personToOwner),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: _Action(
            label: 'Debit',
            icon: AppIcons.receivable,
            tint: palette.receivable,
            onTap: () => _add(context, ref, MoneyFlow.ownerToPerson),
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tint,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: filled ? AccounicColors.actionGradient : null,
            color: filled
                ? null
                : hovered
                    ? palette.raised
                    : palette.sunken,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: filled
                  ? Colors.transparent
                  : hovered
                      ? (tint ?? palette.lineStrong).withValues(alpha: 0.5)
                      : palette.line,
            ),
            boxShadow: [
              if (hovered && filled)
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.34),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: AppIconSize.sm,
                color: filled ? Colors.white : tint,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: filled ? Colors.white : context.colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit, archive, delete.
///
/// Delete is always listed. Hiding it while the account has history meant the
/// menu simply had no Delete in it, which reads as the action being broken
/// rather than as being unavailable — and it left the person no route to the
/// thing they should do instead. It is shown greyed with the count that blocks
/// it and the alternative named, so the menu answers the question it raises.
class PersonMenu extends ConsumerWidget {
  const PersonMenu({super.key, required this.page});

  final PersonPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = page.person;
    final palette = context.money;

    Widget item(IconData icon, String label, {Color? tone, String? note}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: note == null ? 0 : 1),
              child: Icon(icon, size: AppIconSize.sm, color: tone ?? palette.inkMuted),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: tone ?? context.colors.onSurface,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

    // The same test the server applies. `transactionCount` and `totalSettled`
    // both exclude voided rows, and `delete_person()` now counts live rows only,
    // so the two agree — which they did not before: a person whose transactions
    // had all been voided reported zero here, was offered Delete, and was then
    // refused by a server that was still counting the voided rows.
    final transactions = page.balance.transactionCount;
    final settled = page.balance.totalSettled;
    final deletable = transactions == 0 && settled == 0;

    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      color: palette.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.fieldAll,
        side: BorderSide(color: palette.lineStrong),
      ),
      icon: Icon(AppIcons.more, size: AppIconSize.md, color: palette.inkMuted),
      onSelected: (value) async {
        final repository = ref.read(ledgerRepositoryProvider);

        switch (value) {
          case 'edit':
            await showPersonSheet(context, ref, person: person);

          case 'archive':
          case 'restore':
            final archiving = value == 'archive';
            final ok = await confirm(
              context,
              destructive: false,
              icon: AppIcons.archive,
              title: archiving ? 'Archive ${person.name}?' : 'Restore ${person.name}?',
              confirmLabel: archiving ? 'Archive' : 'Restore',
              body: archiving
                  ? 'They are hidden from the people list and from your totals. '
                      'Every transaction and settlement is kept, and you can restore '
                      'them at any time.'
                  : 'They will appear in your people list and totals again.',
            );
            if (!ok) return;
            try {
              await repository.setPersonArchived(person.id, archiving);
              ref.refreshLedger(personId: person.id);
            } on Failure catch (failure) {
              if (context.mounted) showMessage(context, failure.message, error: true);
            }

          case 'delete':
            final ok = await confirm(
              context,
              icon: AppIcons.delete,
              title: 'Delete ${person.name}?',
              confirmLabel: 'Delete',
              body: 'This cannot be undone. It is only possible because there are no '
                  'transactions on this account.',
            );
            if (!ok) return;
            try {
              await repository.deletePerson(person.id);
              ref.refreshLedger();
              if (context.mounted) context.pop();
            } on Failure catch (failure) {
              if (context.mounted) showMessage(context, failure.message, error: true);
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'edit', child: item(AppIcons.edit, 'Edit details')),
        PopupMenuItem(
          value: person.isArchived ? 'restore' : 'archive',
          child: item(AppIcons.archive, person.isArchived ? 'Restore' : 'Archive'),
        ),
        PopupMenuItem(
          value: 'delete',
          enabled: deletable,
          child: item(
            AppIcons.delete,
            'Delete',
            tone: deletable ? palette.payable : palette.inkFaint,
            note: switch (deletable) {
              true => null,
              false when transactions > 0 =>
                '$transactions ${transactions == 1 ? 'transaction' : 'transactions'} '
                    'on this account — archive instead',
              false => 'A settlement is still recorded here — archive instead',
            },
          ),
        ),
      ],
    );
  }
}

/// One timeline row.
///
/// Tapping expands the actions for that row only — a toolbar on every line makes
/// a dense ledger unreadable (context.md §16). The expansion is animated so the
/// rows below it move rather than jump, which is what tells the eye the panel
/// belongs to the row it came out of.
class TimelineTile extends ConsumerStatefulWidget {
  const TimelineTile({
    super.key,
    required this.entry,
    required this.page,
    required this.currency,
    this.divider = true,
  });

  final TimelineEntry entry;
  final PersonPage page;
  final String currency;
  final bool divider;

  @override
  ConsumerState<TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends ConsumerState<TimelineTile> {
  bool _open = false;
  bool _busy = false;

  Future<void> _void() async {
    final entry = widget.entry;
    final isTransaction = !entry.isSettlement;

    final ok = await confirm(
      context,
      icon: isTransaction ? AppIcons.delete : AppIcons.settlement,
      title: isTransaction ? 'Void this transaction?' : 'Reverse this settlement?',
      confirmLabel: isTransaction ? 'Void' : 'Reverse',
      body: isTransaction
          ? 'The transaction stays in the timeline as history but stops counting '
              'towards any balance. If it has already been settled, void those '
              'settlements first.'
          : '${formatMinor(entry.amountMinor, currency: widget.currency)} goes back to '
              'outstanding. The record stays in the timeline marked as reversed.',
    );
    if (!ok) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(ledgerRepositoryProvider);
      if (isTransaction) {
        await repository.voidTransaction(entry.id);
      } else {
        await repository.voidSettlement(entry.id);
      }
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
    final entry = widget.entry;
    final palette = context.money;

    final (background, foreground, border) = entry.isSettlement
        ? (palette.sunken, palette.inkMuted, palette.line)
        : entry.isReceivable
            ? (palette.receivableSoft, palette.receivable, palette.receivableLine)
            : (palette.payableSoft, palette.payable, palette.payableLine);

    final icon = entry.isSettlement
        ? AppIcons.settlement
        : entry.isReceivable
            ? AppIcons.receivable
            : AppIcons.payable;

    return Opacity(
      opacity: entry.isVoid ? 0.55 : 1,
      child: Column(
        children: [
          Hoverable(
            builder: (context, hovered) => AnimatedContainer(
              duration: Motion.fast,
              color: _open
                  ? palette.sunken
                  : hovered
                      ? palette.sunken
                      : Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: border),
                        ),
                        child: Icon(icon, size: AppIconSize.sm, color: foreground),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    entry.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                if (entry.isVoid)
                                  const StatusChip('Voided', tone: StatusTone.muted)
                                else if (entry.status == SettlementStatus.settled)
                                  const StatusChip('Settled', tone: StatusTone.done)
                                else if (entry.status == SettlementStatus.partial)
                                  StatusChip(
                                    '${formatMinor(entry.remainingMinor ?? 0, currency: widget.currency)} left',
                                    tone: StatusTone.partial,
                                  ),
                              ],
                            ),
                            if (entry.note != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                entry.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: palette.inkFaint),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      MoneyText(
                        entry.amountMinor,
                        currency: widget.currency,
                        strikethrough: entry.isVoid,
                        tone: entry.isSettlement
                            ? MoneyTone.neutral
                            : entry.isReceivable
                                ? MoneyTone.receivable
                                : MoneyTone.payable,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedRotation(
                        duration: Motion.fast,
                        curve: Motion.enter,
                        turns: _open ? 0.5 : 0,
                        child: Icon(
                          AppIcons.expand,
                          size: AppIconSize.sm,
                          color: palette.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          AnimatedSize(
            duration: Motion.normal,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : _RowActions(
                    entry: entry,
                    page: widget.page,
                    currency: widget.currency,
                    busy: _busy,
                    onVoid: _void,
                  ),
          ),

          if (widget.divider)
            Divider(height: 1, color: palette.line, indent: AppSpacing.lg),
        ],
      ),
    );
  }
}

/// What can be done to one entry, revealed under it.
class _RowActions extends ConsumerWidget {
  const _RowActions({
    required this.entry,
    required this.page,
    required this.currency,
    required this.busy,
    required this.onVoid,
  });

  final TimelineEntry entry;
  final PersonPage page;
  final String currency;
  final bool busy;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.money;

    return Container(
      width: double.infinity,
      color: palette.sunken,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              fullDate(entry.entryDate),
              if (!entry.isSettlement && (entry.remainingMinor ?? 0) > 0)
                '${formatMinor(entry.remainingMinor!, currency: currency)} still outstanding',
            ].join('  ·  '),
            style: TextStyle(fontSize: 12, color: palette.inkFaint),
          ),
          const SizedBox(height: AppSpacing.md),
          if (entry.isVoid)
            Text(
              'This entry was voided. It stays here as history and does not '
              'affect any balance.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.inkFaint),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (!entry.isSettlement && (entry.remainingMinor ?? 0) > 0)
                  _RowAction(
                    label: 'Settle this',
                    icon: AppIcons.settlement,
                    onTap: busy
                        ? null
                        : () async {
                            final saved = await showSettleSheet(
                              context,
                              ref,
                              balance: page.balance,
                              openTransactions: page.openTransactions,
                              presetTransactionId: entry.id,
                            );
                            if (saved && context.mounted) {
                              showMessage(context, 'Settlement recorded.');
                            }
                          },
                  ),
                if (!entry.isSettlement)
                  _RowAction(
                    label: 'Edit',
                    icon: AppIcons.edit,
                    onTap: busy
                        ? null
                        : () async {
                            final saved = await showTransactionSheet(
                              context,
                              ref,
                              person: PersonRef(page.person.id, page.person.name),
                              transaction: EditableTransaction(
                                id: entry.id,
                                type: entry.txnType ?? TxnType.credit,
                                amountMinor: entry.amountMinor,
                                date: entry.entryDate,
                                description: entry.note,
                              ),
                            );
                            if (saved && context.mounted) {
                              showMessage(context, 'Transaction updated.');
                            }
                          },
                  ),
                _RowAction(
                  label: entry.isSettlement ? 'Reverse' : 'Void',
                  icon: AppIcons.delete,
                  tone: palette.payable,
                  onTap: busy ? null : onVoid,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.tone,
  });

  final String label;
  final IconData icon;
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
          decoration: BoxDecoration(
            color: hovered ? palette.raised : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: hovered ? palette.lineStrong : palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppIconSize.xs, color: color),
              const SizedBox(width: AppSpacing.sm - 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Credited, debited, settled, remaining — the four figures the position is made
/// of, laid out two by two so they fit a phone without shrinking.
class _Figures extends StatelessWidget {
  const _Figures({required this.balance, required this.currency, required this.tone});

  final PersonBalance balance;
  final String currency;
  final BalanceTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    Widget cell(String label, IconData? icon, int minor, MoneyTone moneyTone, Color? color) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md + 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: AppIconSize.xs, color: color ?? palette.inkFaint),
                      const SizedBox(width: AppSpacing.xs + 2),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: palette.inkMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MoneyText(
                    minor,
                    currency: currency,
                    tone: moneyTone,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );

    // The engine's total_credit is the owner-to-person direction, which the
    // product calls a debit — see docs/accounting-direction.md.
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(
                'Credited to you',
                AppIcons.payable,
                balance.totalDebit,
                balance.totalDebit > 0 ? MoneyTone.payable : MoneyTone.neutral,
                balance.totalDebit > 0 ? palette.payable : null,
              ),
              VerticalDivider(width: 1, color: palette.line),
              cell(
                'Debited to them',
                AppIcons.receivable,
                balance.totalCredit,
                balance.totalCredit > 0 ? MoneyTone.receivable : MoneyTone.neutral,
                balance.totalCredit > 0 ? palette.receivable : null,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: palette.line),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cell(
                'Settled',
                AppIcons.settlement,
                balance.totalSettled,
                MoneyTone.neutral,
                null,
              ),
              VerticalDivider(width: 1, color: palette.line),
              cell(
                tone == BalanceTone.payable ? 'You will pay' : 'You will receive',
                AppIcons.net,
                tone == BalanceTone.payable
                    ? balance.outstandingPayable
                    : balance.outstandingReceivable,
                switch (tone) {
                  BalanceTone.payable => MoneyTone.payable,
                  BalanceTone.receivable => MoneyTone.receivable,
                  BalanceTone.settled => MoneyTone.neutral,
                },
                null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonSkeleton extends StatelessWidget {
  const _PersonSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: context.cardPadding,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 130, height: 11),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 190, height: 38),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 120, height: 13),
                    SizedBox(height: AppSpacing.xl),
                    Skeleton(height: 46, radius: AppRadius.field),
                  ],
                ),
              ),
              Divider(height: 1, color: context.money.line),
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(child: Skeleton(width: 100, height: 34)),
                    SizedBox(width: AppSpacing.xxl),
                    Expanded(child: Skeleton(width: 100, height: 34)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Card(child: SkeletonList(rows: 5)),
      ],
    );
  }
}
