import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../shell.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'search_sheet.dart';

/// Dashboard (context.md §13).
///
/// One question, answered in the first two seconds: how am I doing right now?
///
/// The order is deliberate and it is the order the answer arrives in — the two
/// sides side by side, the position they add up to, then who it is with. Nothing
/// here is a widget for its own sake: no charts beyond the single trend line
/// beside the net figure, no analytics, no reporting engine.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: wide ? const Text('Dashboard') : const AccounicLogo(markSize: 24, fontSize: 16),
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
              ErrorNote('$error', onRetry: () => ref.invalidate(dashboardProvider)),
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

    final owed = data.peopleWithBalance.where((p) => p.netBalance > 0).length;
    final owing = data.peopleWithBalance.where((p) => p.netBalance < 0).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        PageBody(
          maxWidth: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -------------------------------------------------------- greeting
              Reveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${greeting()}, ${data.name.split(' ').first}',
                      style: TextStyle(fontSize: 13, color: context.money.inkMuted),
                    ),
                    const SizedBox(height: 3),
                    Text('Your money at a glance', style: context.display(24)),
                    if (data.today.count > 0) ...[
                      const SizedBox(height: 10),
                      _TodayChips(today: data.today, currency: currency),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ----------------------------------------- the two sides, compact
              Reveal(
                delay: const Duration(milliseconds: 50),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SideCard(
                        label: 'Receivable',
                        caption: 'Money owed to you',
                        minor: summary.totalReceivable,
                        currency: currency,
                        tone: MoneyTone.receivable,
                        accounts: owed,
                        icon: Icons.north_east_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SideCard(
                        label: 'Payable',
                        caption: 'Money you owe',
                        minor: summary.totalPayable,
                        currency: currency,
                        tone: MoneyTone.payable,
                        accounts: owing,
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ---------------------------------------------------- the answer
              Reveal(
                delay: const Duration(milliseconds: 100),
                child: _NetCard(summary: summary, currency: currency),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------- who it is with
              Reveal(
                delay: const Duration(milliseconds: 150),
                child: SectionCard(
                  title: 'Outstanding balances',
                  action: TextButton(
                    onPressed: () => context.go('/people'),
                    child: const Text('View all'),
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
                      : Stagger(
                          children: [
                            for (final person in data.peopleWithBalance)
                              PersonRow(person: person, currency: currency),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              Reveal(
                delay: const Duration(milliseconds: 190),
                child: SectionCard(
                  title: 'Recent activity',
                  action: TextButton(
                    onPressed: () => context.go('/activity'),
                    child: const Text('View all'),
                  ),
                  child: data.recentActivity.isEmpty
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No transactions yet',
                          description: 'Record one and it will appear here straight away.',
                        )
                      : Stagger(
                          children: [
                            for (final item in data.recentActivity.take(wide ? 8 : 5))
                              ActivityRow(item: item, currency: currency),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Today's movement, as chips rather than a sentence — three small figures read
/// faster than one line of prose containing three figures.
class _TodayChips extends StatelessWidget {
  const _TodayChips({required this.today, required this.currency});

  final TodayTotals today;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    Widget chip(String amount, String label, Color color, Color background, Color border) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              amount,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.75))),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Today', style: TextStyle(fontSize: 12, color: palette.inkFaint)),
        // The engine's `credit` bucket is the owner-to-person direction, which
        // the product calls a debit — see docs/accounting-direction.md.
        if (today.debit > 0)
          chip(formatMinor(today.debit, currency: currency), 'credited', palette.payable,
              palette.payableSoft, palette.payableLine),
        if (today.credit > 0)
          chip(formatMinor(today.credit, currency: currency), 'debited', palette.receivable,
              palette.receivableSoft, palette.receivableLine),
        if (today.settled > 0)
          chip(formatMinor(today.settled, currency: currency), 'settled', palette.inkMuted,
              palette.sunken, palette.line),
      ],
    );
  }
}

/// One of the two sides. Half a phone wide, so it carries a figure, what it
/// means, and how many accounts it came from — and nothing else. No sparkline
/// here: a trend line at this size is decoration, and the net card below already
/// carries the one the screen needs.
class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.label,
    required this.caption,
    required this.minor,
    required this.currency,
    required this.tone,
    required this.accounts,
    required this.icon,
  });

  final String label;
  final String caption;
  final int minor;
  final String currency;
  final MoneyTone tone;
  final int accounts;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final color = tone == MoneyTone.receivable ? palette.receivable : palette.payable;
    final soft = tone == MoneyTone.receivable ? palette.receivableSoft : palette.payableSoft;
    final line = tone == MoneyTone.receivable ? palette.receivableLine : palette.payableLine;

    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: line),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              minor,
              currency: currency,
              color: color,
              style: context.display(23),
            ),
          ),
          const SizedBox(height: 6),
          Text(caption, style: TextStyle(fontSize: 12, color: palette.inkMuted)),
          const SizedBox(height: 2),
          Text(
            accounts == 0 ? '—' : '$accounts ${accounts == 1 ? 'account' : 'accounts'}',
            style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// The hero. It is the answer the other two cards add up to, so it is the only
/// thing on the screen that gets the brand hairline.
class _NetCard extends StatelessWidget {
  const _NetCard({required this.summary, required this.currency});

  final OwnerSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final net = summary.netPosition;
    final tone = switch (balanceTone(net)) {
      BalanceTone.receivable => MoneyTone.receivable,
      BalanceTone.payable => MoneyTone.payable,
      BalanceTone.settled => MoneyTone.neutral,
    };
    final color = tone.color(context, net);

    return SectionCard(
      raised: true,
      brandRule: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net balance', style: TextStyle(fontSize: 13, color: palette.inkMuted)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              net.abs(),
              currency: currency,
              color: color,
              style: context.display(34),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            net > 0
                ? "You're ahead"
                : net < 0
                    ? 'You are behind'
                    : 'Everything is settled',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: net == 0 ? palette.inkFaint : color,
            ),
          ),
          const SizedBox(height: 14),
          SplitBar(receivable: summary.totalReceivable, payable: summary.totalPayable),
          if (summary.totalReceivable > 0 && summary.totalPayable > 0) ...[
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatMinor(summary.totalReceivable, currency: currency)} in',
                  style: TextStyle(fontSize: 11.5, color: palette.receivable),
                ),
                Text(
                  '${formatMinor(summary.totalPayable, currency: currency)} out',
                  style: TextStyle(fontSize: 11.5, color: palette.payable),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A person and where they stand — the balance is the anchor (context.md §5).
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.currency,
    this.subtitle,
    this.divider = true,
  });

  final PersonBalance person;
  final String currency;
  final String? subtitle;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final meta = subtitle ??
        (person.lastActivityAt == null ? 'No activity yet' : friendlyDate(person.lastActivityAt!));

    return Column(
      children: [
        InkWell(
          onTap: () => context.push('/people/${person.personId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Avatar(person.name, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: context.money.inkFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                NetBadge(netMinor: person.netBalance, currency: currency),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: context.money.inkFaint),
              ],
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}

/// One activity entry. Shared by the dashboard and the activity screen so the
/// two never drift apart.
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.item,
    required this.currency,
    this.divider = true,
    this.showDate = true,
  });

  final ActivityItem item;
  final String currency;
  final bool divider;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final (background, foreground, border) = item.isSettlement
        ? (palette.sunken, palette.inkMuted, palette.line)
        : item.isReceivable
            ? (palette.receivableSoft, palette.receivable, palette.receivableLine)
            : (palette.payableSoft, palette.payable, palette.payableLine);

    final meta = [
      item.label,
      if (item.note != null) item.note!,
      if (showDate) friendlyDate(item.entryDate),
    ].join(' · ');

    return Column(
      children: [
        InkWell(
          onTap: () => context.push('/people/${item.personId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
                  child: Icon(
                    item.isSettlement
                        ? Icons.swap_horiz_rounded
                        : item.isReceivable
                            ? Icons.north_east_rounded
                            : Icons.south_west_rounded,
                    size: 18,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.personName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.inkFaint),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                MoneyText(
                  item.amountMinor,
                  currency: currency,
                  tone: item.isSettlement
                      ? MoneyTone.neutral
                      : item.isReceivable
                          ? MoneyTone.receivable
                          : MoneyTone.payable,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        const Skeleton(width: 120, height: 13),
        const SizedBox(height: 10),
        const Skeleton(width: 220, height: 24),
        const SizedBox(height: 22),
        Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              const Expanded(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 90, height: 13),
                        SizedBox(height: 14),
                        Skeleton(width: 110, height: 24),
                        SizedBox(height: 10),
                        Skeleton(width: 80, height: 11),
                      ],
                    ),
                  ),
                ),
              ),
              if (i == 0) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 10),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 90, height: 13),
                SizedBox(height: 14),
                Skeleton(width: 170, height: 34),
                SizedBox(height: 14),
                Skeleton(height: 4, radius: 3),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Card(child: SkeletonList(rows: 4)),
      ],
    );
  }
}
