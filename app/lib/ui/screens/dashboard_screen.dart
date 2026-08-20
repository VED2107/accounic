import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'search_sheet.dart';

/// Dashboard (context.md §13).
///
/// Answers "what is my current financial position?" in the first screenful:
/// three numbers, then who they are with, then what just happened. One RPC call
/// supplies all of it.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (!wide)
            IconButton(
              onPressed: () => showSearchSheet(context, ref),
              icon: const Icon(Icons.search),
              tooltip: 'Search',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(dashboardProvider.future),
        child: async.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ErrorNote(
                '$error',
                onRetry: () => ref.invalidate(dashboardProvider),
              ),
            ],
          ),
          data: (data) => _DashboardBody(data: data),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final Dashboard data;

  @override
  Widget build(BuildContext context) {
    final currency = data.currency;
    final summary = data.summary;
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    final netTone = switch (balanceTone(summary.netPosition)) {
      BalanceTone.receivable => MoneyTone.receivable,
      BalanceTone.payable => MoneyTone.payable,
      BalanceTone.settled => MoneyTone.neutral,
    };

    final stats = [
      SectionCard(
        padding: const EdgeInsets.all(18),
        child: MoneyStat(
          label: 'Receivable',
          minor: summary.totalReceivable,
          currency: currency,
          tone: MoneyTone.receivable,
          sublabel: 'Money owed to you',
        ),
      ),
      SectionCard(
        padding: const EdgeInsets.all(18),
        child: MoneyStat(
          label: 'Payable',
          minor: summary.totalPayable,
          currency: currency,
          tone: MoneyTone.payable,
          sublabel: 'Money you owe',
        ),
      ),
      SectionCard(
        padding: const EdgeInsets.all(18),
        child: MoneyStat(
          label: 'Net',
          minor: summary.netPosition.abs(),
          currency: currency,
          tone: netTone,
          sublabel: summary.netPosition > 0
              ? 'In your favour'
              : summary.netPosition < 0
                  ? 'Against you'
                  : 'Everything is settled',
        ),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        PageBody(
          maxWidth: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${greeting()}, ${data.name.split(' ').first}',
                style: TextStyle(fontSize: 13.5, color: context.money.inkMuted),
              ),
              const SizedBox(height: 2),
              const Text(
                'Your money overview',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4),
              ),
              const SizedBox(height: 18),

              if (wide)
                Row(
                  children: [
                    for (final (i, stat) in stats.indexed) ...[
                      Expanded(child: stat),
                      if (i != stats.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    for (final stat in stats) ...[stat, const SizedBox(height: 10)],
                  ],
                ),

              if (data.today.count > 0) ...[
                const SizedBox(height: 6),
                _TodayLine(today: data.today, currency: currency),
              ],

              const SizedBox(height: 22),

              SectionCard(
                title: 'Outstanding balances',
                action: TextButton(
                  onPressed: () => context.go('/people'),
                  child: const Text('All people'),
                ),
                child: data.peopleWithBalance.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        title: summary.peopleCount == 0
                            ? 'No people yet'
                            : 'Everything is settled',
                        description: summary.peopleCount == 0
                            ? 'Add your first person or business to start tracking money.'
                            : 'No one owes you and you owe no one.',
                      )
                    : Column(
                        children: [
                          for (final person in data.peopleWithBalance)
                            _PersonRow(person: person, currency: currency),
                        ],
                      ),
              ),

              const SizedBox(height: 14),

              SectionCard(
                title: 'Recent activity',
                action: TextButton(
                  onPressed: () => context.go('/activity'),
                  child: const Text('All activity'),
                ),
                child: data.recentActivity.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No transactions yet',
                        description: 'Your activity will appear here.',
                      )
                    : Column(
                        children: [
                          for (final item in data.recentActivity)
                            ActivityRow(item: item, currency: currency),
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

class _TodayLine extends StatelessWidget {
  const _TodayLine({required this.today, required this.currency});

  final TodayTotals today;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (today.credit > 0) '${formatMinor(today.credit, currency: currency)} credit',
      if (today.debit > 0) '${formatMinor(today.debit, currency: currency)} debit',
      if (today.settled > 0) '${formatMinor(today.settled, currency: currency)} settled',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      'Today: ${parts.join(' · ')}',
      style: TextStyle(fontSize: 13, color: context.money.inkMuted),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.currency});

  final PersonBalance person;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: () => context.push('/people/${person.personId}'),
          leading: Avatar(person.name, size: 38),
          title: Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: person.lastActivityAt == null
              ? null
              : Text(friendlyDate(person.lastActivityAt!),
                  style: const TextStyle(fontSize: 12)),
          trailing: NetBadge(netMinor: person.netBalance, currency: currency),
        ),
        Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// One activity entry. Shared by the dashboard and the activity screen so the
/// two never drift apart.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.item, required this.currency, this.divider = true});

  final ActivityItem item;
  final String currency;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final (background, foreground) = item.isSettlement
        ? (palette.sunken, palette.inkMuted)
        : item.isReceivable
            ? (palette.receivableSoft, palette.receivable)
            : (palette.payableSoft, palette.payable);

    return Column(
      children: [
        ListTile(
          onTap: () => context.push('/people/${item.personId}'),
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.isSettlement
                  ? Icons.swap_horiz
                  : item.isReceivable
                      ? Icons.south_west
                      : Icons.north_east,
              size: 18,
              color: foreground,
            ),
          ),
          title: Text(
            item.personName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              item.label,
              if (item.note != null) item.note!,
              friendlyDate(item.entryDate),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: MoneyText(
            item.amountMinor,
            currency: currency,
            tone: item.isSettlement
                ? MoneyTone.neutral
                : item.isReceivable
                    ? MoneyTone.receivable
                    : MoneyTone.payable,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        if (divider)
          Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        const Skeleton(width: 120, height: 13),
        const SizedBox(height: 10),
        const Skeleton(width: 200, height: 22),
        const SizedBox(height: 20),
        for (var i = 0; i < 3; i++) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Skeleton(width: 90, height: 13),
                  SizedBox(height: 10),
                  Skeleton(width: 150, height: 26),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        const Card(child: SkeletonList(rows: 4)),
      ],
    );
  }
}
