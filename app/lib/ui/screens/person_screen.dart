import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/failure.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../sheets/person_sheet.dart';
import '../sheets/settle_sheet.dart';
import '../sheets/sheet_scaffold.dart';
import '../sheets/transaction_sheet.dart';
import '../widgets/common.dart';

/// Person / business account — the screen the product is really about
/// (context.md §6, §16).
///
/// Credit and debit appear together, never in separate modules, and the net
/// position is the largest thing on the page so "where do we stand?" needs no
/// arithmetic from the reader.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(personPageProvider(personId));
    final currency = ref.watch(currencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.person.name ?? 'Account'),
        actions: [
          if (async.hasValue)
            _OverflowMenu(page: async.value!, personId: personId),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const _PersonSkeleton(),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ErrorNote('$error', onRetry: () => ref.invalidate(personPageProvider(personId))),
          ],
        ),
        data: (page) => RefreshIndicator(
          onRefresh: () async => ref.refresh(personPageProvider(personId).future),
          child: _PersonBody(page: page, currency: currency),
        ),
      ),
    );
  }
}

class _PersonBody extends ConsumerWidget {
  const _PersonBody({required this.page, required this.currency});

  final PersonPage page;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = page.person;
    final balance = page.balance;
    final tone = balanceTone(balance.netBalance);
    final groups = groupByDate(page.timeline, (entry) => entry.entryDate);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- identity -------------------------------------------------
              Row(
                children: [
                  Avatar(person.name, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                        ),
                        Text(
                          [
                            person.type.label,
                            if (person.phone != null) person.phone!,
                            if (person.isArchived) 'Archived',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: context.money.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---- position: both sides on one page (context.md §6) ---------
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _SidePanel(
                              label: 'You will receive',
                              minor: balance.outstandingReceivable,
                              currency: currency,
                              tone: balance.outstandingReceivable > 0
                                  ? MoneyTone.receivable
                                  : MoneyTone.neutral,
                            ),
                          ),
                          VerticalDivider(width: 1, color: context.money.line),
                          Expanded(
                            child: _SidePanel(
                              label: 'You will pay',
                              minor: balance.outstandingPayable,
                              currency: currency,
                              tone: balance.outstandingPayable > 0
                                  ? MoneyTone.payable
                                  : MoneyTone.neutral,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: context.money.line),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Net balance',
                              style: TextStyle(fontSize: 13.5, color: context.money.inkMuted)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: MoneyText(
                              balance.netBalance.abs(),
                              currency: currency,
                              tone: switch (tone) {
                                BalanceTone.receivable => MoneyTone.receivable,
                                BalanceTone.payable => MoneyTone.payable,
                                BalanceTone.settled => MoneyTone.neutral,
                              },
                              style: const TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            switch (tone) {
                              BalanceTone.receivable => 'receivable',
                              BalanceTone.payable => 'payable',
                              BalanceTone.settled => 'Everything is settled',
                            },
                            style: TextStyle(fontSize: 13, color: context.money.inkFaint),
                          ),
                          const SizedBox(height: 16),
                          _ActionRow(page: page),
                        ],
                      ),
                    ),
                    if (balance.totalSettled > 0) ...[
                      Divider(height: 1, color: context.money.line),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        child: Text(
                          '${formatMinor(balance.totalSettled, currency: currency)} settled so far '
                          'across ${balance.transactionCount} '
                          '${balance.transactionCount == 1 ? 'transaction' : 'transactions'}.',
                          style: TextStyle(fontSize: 12.5, color: context.money.inkFaint),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (person.notes != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NOTES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: context.money.inkFaint,
                            )),
                        const SizedBox(height: 6),
                        Text(person.notes!,
                            style: TextStyle(
                                fontSize: 13.5, height: 1.5, color: context.money.inkMuted)),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ---- timeline (context.md §16) --------------------------------
              const Text('Timeline',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),

              if (page.timeline.isEmpty)
                const Card(
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    description: 'Your activity with this account will appear here.',
                  ),
                )
              else
                for (final group in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                    child: Text(
                      group.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: context.money.inkFaint,
                      ),
                    ),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final entry in group.items)
                          _TimelineTile(
                            entry: entry,
                            page: page,
                            currency: currency,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.label,
    required this.minor,
    required this.currency,
    required this.tone,
  });

  final String label;
  final int minor;
  final String currency;
  final MoneyTone tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: context.money.inkMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              minor,
              currency: currency,
              tone: tone,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.page});

  final PersonPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = page.balance;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (balance.hasOutstanding)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: balance.netBalance >= 0
                  ? context.money.receivable
                  : context.money.payable,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
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
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Settle'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final saved = await showTransactionSheet(
              context,
              ref,
              person: PersonRef(page.person.id, page.person.name),
            );
            if (saved && context.mounted) {
              showMessage(context, 'Transaction saved.');
            }
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add transaction'),
        ),
      ],
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.page, required this.personId});

  final PersonPage page;
  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = page.person;

    return PopupMenuButton<String>(
      tooltip: 'More',
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
        const PopupMenuItem(value: 'edit', child: Text('Edit details')),
        PopupMenuItem(
          value: person.isArchived ? 'restore' : 'archive',
          child: Text(person.isArchived ? 'Restore' : 'Archive'),
        ),
        if (page.balance.transactionCount == 0)
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: context.money.payable)),
          ),
      ],
    );
  }
}

/// One timeline row. Tapping expands the actions for that row only — a toolbar
/// on every line makes a dense ledger unreadable (context.md §16).
class _TimelineTile extends ConsumerStatefulWidget {
  const _TimelineTile({
    required this.entry,
    required this.page,
    required this.currency,
  });

  final TimelineEntry entry;
  final PersonPage page;
  final String currency;

  @override
  ConsumerState<_TimelineTile> createState() => _TimelineTileState();
}

class _TimelineTileState extends ConsumerState<_TimelineTile> {
  bool _open = false;
  bool _busy = false;

  Future<void> _void() async {
    final entry = widget.entry;
    final isTransaction = !entry.isSettlement;

    final ok = await confirm(
      context,
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
    final (background, foreground) = entry.isSettlement
        ? (palette.sunken, palette.inkMuted)
        : entry.isReceivable
            ? (palette.receivableSoft, palette.receivable)
            : (palette.payableSoft, palette.payable);

    return Opacity(
      opacity: entry.isVoid ? 0.55 : 1,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _open = !_open),
            leading: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                entry.isSettlement
                    ? Icons.swap_horiz
                    : entry.isReceivable
                        ? Icons.south_west
                        : Icons.north_east,
                size: 18,
                color: foreground,
              ),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
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
            subtitle: entry.note == null
                ? null
                : Text(entry.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
            trailing: MoneyText(
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
          ),

          if (_open)
            Container(
              width: double.infinity,
              color: palette.sunken,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: entry.isVoid
                  ? Text(
                      'This entry was voided. It stays here as history and does not '
                      'affect any balance.',
                      style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!entry.isSettlement && (entry.remainingMinor ?? 0) > 0)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final saved = await showSettleSheet(
                                      context,
                                      ref,
                                      balance: widget.page.balance,
                                      openTransactions: widget.page.openTransactions,
                                      presetTransactionId: entry.id,
                                    );
                                    if (saved && context.mounted) {
                                      showMessage(context, 'Settlement recorded.');
                                    }
                                  },
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                            child: const Text('Settle this'),
                          ),
                        if (!entry.isSettlement)
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final saved = await showTransactionSheet(
                                      context,
                                      ref,
                                      person: PersonRef(
                                          widget.page.person.id, widget.page.person.name),
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
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                            child: const Text('Edit'),
                          ),
                        OutlinedButton(
                          onPressed: _busy ? null : _void,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            foregroundColor: palette.payable,
                          ),
                          child: Text(entry.isSettlement ? 'Reverse' : 'Void'),
                        ),
                      ],
                    ),
            ),

          Divider(height: 1, color: palette.line, indent: 16, endIndent: 16),
        ],
      ),
    );
  }
}

class _PersonSkeleton extends StatelessWidget {
  const _PersonSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Row(
          children: const [
            Skeleton(width: 48, height: 48, radius: 15),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 180, height: 20),
                  SizedBox(height: 8),
                  Skeleton(width: 120, height: 12),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(width: 120, height: 13),
                SizedBox(height: 10),
                Skeleton(width: 190, height: 30),
                SizedBox(height: 22),
                Skeleton(width: double.infinity, height: 42, radius: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Card(child: SkeletonList(rows: 4)),
      ],
    );
  }
}
