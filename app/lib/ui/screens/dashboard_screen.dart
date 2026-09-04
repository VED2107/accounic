import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/app_page.dart';
import '../widgets/brand.dart';
import '../sheets/transaction_sheet.dart';
import '../widgets/activity_chart.dart';
import '../widgets/common.dart';
import '../widgets/currency_field.dart';
import '../widgets/sparkline.dart';
import 'search_sheet.dart';

/// Dashboard (context.md §13).
///
/// One question, answered in the first two seconds: how am I doing right now?
///
/// The order is deliberate and it is the order the answer arrives in — the
/// position, the two sides it is made of, then who it is with, then what just
/// happened. There is one card carrying the money rather than three of equal
/// weight, because three equal cards ask the reader to work out which one is the
/// answer. Nothing here is a widget for its own sake: no charts beyond the
/// single trend line beside the net figure, no analytics, no reporting engine.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    final compact = context.isCompact;
    final name = async.valueOrNull?.name.split(' ').first ?? '';

    return AppPage(
      title: name.isEmpty ? 'Dashboard' : '${greeting()}, $name',
      subtitle: async.valueOrNull == null
          ? null
          : _standing(async.value!, context),
      // The one screen whose title is the product greeting rather than a noun,
      // and so the one place the brand ramp reads as identity rather than as
      // decoration. Nothing else in the app takes it, and money never does.
      brandTitle: true,
      compactTitle: const AccounicLogo(markSize: 24, fontSize: 16),
      width: ContentWidth.standard,
      bottomPadding: compact ? 120 : 48,
      actions: [
        if (compact)
          AppIconAction(
            icon: AppIcons.search,
            tooltip: 'Search',
            onPressed: () => showSearchSheet(context, ref),
          ),
      ],
      onRefresh: () async => ref.refresh(dashboardProvider.future),
      children: switch (async) {
        AsyncData(:final value) => _body(context, value, compact),
        AsyncError(:final error) => [
            ErrorNote.forError(
              error,
              what: 'your dashboard',
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
          ],
        _ => const [_DashboardSkeleton()],
      },
    );
  }

  /// The subtitle is the answer in one sentence, so a reader who takes nothing
  /// else from the screen still leaves with it.
  static String _standing(Dashboard data, BuildContext context) {
    final net = data.summary.netPosition;
    final people = data.summary.peopleCount;
    final across = people == 0
        ? 'No accounts yet'
        : 'Across $people ${people == 1 ? 'account' : 'accounts'}';

    return switch (balanceTone(net)) {
      BalanceTone.receivable => '$across · you are owed on balance',
      BalanceTone.payable => '$across · you owe on balance',
      BalanceTone.settled => people == 0
          ? 'Add someone to start tracking money'
          : '$across · everything is settled',
    };
  }

  List<Widget> _body(BuildContext context, Dashboard data, bool compact) {
    final currency = data.currency;

    return [
      // On a phone the app bar carries the brand rather than the greeting, so
      // the greeting belongs at the top of the content instead.
      if (compact) ...[
        Reveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrandText(
                '${greeting()}, ${data.name.split(' ').first}',
                style: context.display(22),
              ),
              const SizedBox(height: 3),
              Text(
                _standing(data, context),
                style: TextStyle(fontSize: 13, color: context.money.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],

      Reveal(delay: const Duration(milliseconds: 40), child: PositionCard(data: data)),

      if (data.today.count > 0) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 80),
          child: _TodayStrip(today: data.today, currency: currency),
        ),
      ],

      // Cash in hand, and the opening balance beside it (db/migrations/0022).
      //
      // This card replaced "By currency". The per-currency breakdown answered a
      // question about presentation — the same money before it was converted —
      // and this one answers a question about the ledger: how much of the
      // position is trading, and how much is what the accounts were carried in
      // with. The two figures are calculated independently by the database and
      // are never added together into one number here.
      if (data.cashInHand case final cash?) ...[
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: const Duration(milliseconds: 90),
          child: _CashInHandCard(
            cash: cash,
            opening: data.openingTotal,
            byCurrency: data.totalsByCurrency,
            baseCurrency: currency,
          ),
        ),
      ],

      const SizedBox(height: AppSpacing.xxl),

      // The month in flows (upgrade §8). Below the position, above the lists:
      // it answers "what has been happening", which comes after "where do I
      // stand" and before "with whom".
      Reveal(
        delay: const Duration(milliseconds: 100),
        child: _ActivityChartCard(currency: currency),
      ),

      Reveal(
        delay: const Duration(milliseconds: 120),
        child: SectionCard(
          title: 'Outstanding balances',
          action: data.peopleWithBalance.isEmpty
              ? null
              : TextButton(
                  onPressed: () => context.go('/people'),
                  child: const Text('View all'),
                ),
          child: data.peopleWithBalance.isEmpty
              ? EmptyState(
                  icon: data.summary.peopleCount == 0 ? AppIcons.noPeople : AppIcons.success,
                  title: data.summary.peopleCount == 0
                      ? 'No one is on your ledger yet'
                      : 'Everything is settled',
                  description: data.summary.peopleCount == 0
                      ? 'Add your first person or business to start tracking money.'
                      : 'No one owes you and you owe no one.',
                )
              : Stagger(
                  children: [
                    for (final (index, person) in data.peopleWithBalance.indexed)
                      PersonRow(
                        person: person,
                        currency: currency,
                        divider: index < data.peopleWithBalance.length - 1,
                      ),
                  ],
                ),
        ),
      ),

      const SizedBox(height: AppSpacing.lg),

      Reveal(
        delay: const Duration(milliseconds: 160),
        child: SectionCard(
          title: 'Recent activity',
          action: data.recentActivity.isEmpty
              ? null
              : TextButton(
                  onPressed: () => context.go('/activity'),
                  child: const Text('View all'),
                ),
          child: data.recentActivity.isEmpty
              ? EmptyState(
                  icon: AppIcons.quiet,
                  title: 'Your ledger is quiet',
                  description: 'Record a transaction and it will appear here straight away.',
                  // An empty state that explains but does not help leaves the
                  // user to go and find the fix themselves (upgrade §11).
                  // A Consumer rather than threading a ref through _body: the
                  // sheet is the only thing on this branch that needs one.
                  action: Consumer(
                    builder: (context, ref, _) => FilledButton.icon(
                      onPressed: () => showTransactionSheet(context, ref),
                      icon: const Icon(AppIcons.add, size: AppIconSize.sm),
                      label: const Text('Add transaction'),
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final rows = data.recentActivity.take(compact ? 5 : 8).toList();
                    return Stagger(
                      children: [
                        for (final (index, item) in rows.indexed)
                          ActivityRow(
                            item: item,
                            currency: currency,
                            divider: index < rows.length - 1,
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    ];
  }
}

/// The whole money picture, in one card.
///
/// Net position is the headline because it is the only figure that answers the
/// question on its own. Receivable and payable sit below it as the two halves it
/// is made of — smaller, paired, divided by a hairline, with the split bar
/// underneath showing the proportion between them. One card, three levels of
/// hierarchy, no repetition.
class PositionCard extends ConsumerWidget {
  const PositionCard({super.key, required this.data});

  final Dashboard data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.money;
    final summary = data.summary;
    final currency = data.currency;
    final net = summary.netPosition;
    final tone = balanceTone(net);

    final color = switch (tone) {
      BalanceTone.receivable => palette.receivable,
      BalanceTone.payable => palette.payable,
      BalanceTone.settled => context.colors.onSurface,
    };

    final owed = data.peopleWithBalance.where((p) => p.netBalance > 0).length;
    final owing = data.peopleWithBalance.where((p) => p.netBalance < 0).length;

    return SectionCard(
      raised: true,
      brandRule: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.isCompact ? AppSpacing.lg : AppSpacing.xl,
              AppSpacing.lg + 2,
              context.isCompact ? AppSpacing.lg : AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.net, size: AppIconSize.xs, color: palette.inkFaint),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text('NET POSITION', style: context.statLabel),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedMoney(
                          net.abs(),
                          currency: currency,
                          color: color,
                          // The one number this screen is about. One size
                          // token, not a hand-tuned figure per breakpoint.
                          style: context
                              .moneyStyle(MoneySize.hero)
                              .copyWith(fontSize: context.isCompact ? 34 : 40),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm - 1),
                      Text(
                        switch (tone) {
                          BalanceTone.receivable => "You're ahead",
                          BalanceTone.payable => 'You are behind',
                          BalanceTone.settled => 'Everything is settled',
                        },
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: tone == BalanceTone.settled ? palette.inkMuted : color,
                        ),
                      ),
                      // Totals across currencies are only as complete as the
                      // rates behind them. Saying how many accounts could not be
                      // converted is more honest than quietly leaving them out
                      // of a headline figure (upgrade §9).
                      if (summary.currencyCount > 1) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Converted to $currency',
                          style: context.statNote,
                        ),
                      ],
                      if (summary.unconvertedPeople > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${summary.unconvertedPeople} '
                          '${summary.unconvertedPeople == 1 ? 'account is' : 'accounts are'} '
                          'not included — no exchange rate yet',
                          style: TextStyle(fontSize: 12.5, height: 1.35, color: palette.payable),
                        ),
                      ],
                    ],
                  ),
                ),
                // The trend is context, not a report: where the position has
                // been moving over the last month, at the size of a signature.
                if (!context.isCompact) ...[
                  const SizedBox(width: AppSpacing.xxl),
                  SizedBox(
                    width: 150,
                    child: _NetTrend(color: color, currency: currency),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: palette.line),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Side(
                    label: 'Receivable',
                    caption: 'Money owed to you',
                    icon: AppIcons.receivable,
                    minor: summary.totalReceivable,
                    currency: currency,
                    color: palette.receivable,
                    accounts: owed,
                  ),
                ),
                VerticalDivider(width: 1, color: palette.line),
                Expanded(
                  child: _Side(
                    label: 'Payable',
                    caption: 'Money you owe',
                    icon: AppIcons.payable,
                    minor: summary.totalPayable,
                    currency: currency,
                    color: palette.payable,
                    accounts: owing,
                  ),
                ),
              ],
            ),
          ),
          if (summary.totalReceivable > 0 && summary.totalPayable > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.isCompact ? AppSpacing.lg : AppSpacing.xl,
                0,
                context.isCompact ? AppSpacing.lg : AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: SplitBar(
                receivable: summary.totalReceivable,
                payable: summary.totalPayable,
              ),
            ),
        ],
      ),
    );
  }
}

/// One half of the position.
class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.caption,
    required this.icon,
    required this.minor,
    required this.currency,
    required this.color,
    required this.accounts,
  });

  final String label;
  final String caption;
  final IconData icon;
  final int minor;
  final String currency;
  final Color color;
  final int accounts;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.isCompact ? AppSpacing.lg : AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppIconSize.xs, color: color),
              const SizedBox(width: AppSpacing.xs + 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              minor,
              currency: currency,
              color: color,
              style: context.display(context.isCompact ? 20 : 23),
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          Text(
            accounts == 0
                ? caption
                : '$caption · $accounts ${accounts == 1 ? 'account' : 'accounts'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Thirty days of daily flow, tappable for one day at a time.
///
/// Renders nothing at all until there are at least two days of history: an
/// empty chart is worse than no chart, because it looks like a chart that
/// failed rather than a ledger that is new.
class _ActivityChartCard extends ConsumerWidget {
  const _ActivityChartCard({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(activitySummaryProvider).valueOrNull;
    if (buckets == null || buckets.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: SectionCard(
        title: 'Last 30 days',
        padding: context.cardPadding,
        child: ActivityChart(buckets: buckets, currency: currency),
      ),
    );
  }
}

/// Where the position has been going, built from the same daily buckets the
/// activity screen totals. Cumulative, because a chart of daily movement says
/// nothing about where the ledger stands.
class _NetTrend extends ConsumerWidget {
  const _NetTrend({required this.color, required this.currency});

  /// What the scale and the ending value are denominated in.
  final String currency;

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buckets = ref.watch(activitySummaryProvider).valueOrNull;
    if (buckets == null || buckets.length < 3) return const SizedBox.shrink();

    // The engine's `credit` bucket is the owner-to-person direction — the
    // receivable one — and `debit` is the payable one. See
    // docs/accounting-direction.md; nothing outside that rule is decided here.
    var running = 0;
    final points = <int>[];
    for (final bucket in buckets) {
      running += bucket.credit - bucket.debit;
      points.add(running);
    }

    // Lending less borrowing, accumulated across the window and starting from
    // zero on its first day. It is NOT the net position printed beside it — the
    // net position includes every account's whole history and every settlement,
    // and the two are routinely an order of magnitude apart — so the caption
    // says what this actually is rather than borrowing the other figure's name.
    return SparklineFigure(
      points: points,
      color: color,
      currency: currency,
      label: 'LAST 30 DAYS',
      caption: 'Lent less borrowed, cumulative',
    );
  }
}

/// Every currency that carries entries, one row each (db/migrations/0015).
///
/// The position card above converts everything into the workspace currency,
/// which is the only way one number can answer "how am I doing". That number
/// cannot show what the dirham half of it was, so this does — unconverted, and
/// summed only within each currency. The workspace currency gets the same row
/// as any other, so a single-currency ledger reads exactly like a four-currency
/// one rather than looking like a panel for foreign money.
/// Cash in hand, and the opening balance beside it (db/migrations/0022).
///
/// The rule this card exists to make visible: **cash in hand never contains an
/// opening balance**. They are two positions, each summed from its own half of
/// the ledger by the database, and the only place they are added together is
/// the position card above — which says so.
class _CashInHandCard extends StatelessWidget {
  const _CashInHandCard({
    required this.cash,
    required this.opening,
    required this.byCurrency,
    required this.baseCurrency,
  });

  final WorkspacePosition cash;
  final WorkspacePosition? opening;

  /// The same money before it was converted, one row per currency it was
  /// actually entered in (db/migrations/0017, split by 0022).
  final List<CurrencyTotals> byCurrency;
  final String baseCurrency;

  /// The original figures behind a converted total, as one line.
  ///
  /// A total in the workspace currency only exists because the dirhams were
  /// converted into rupees first; this says what they were before that step.
  /// Rows in the workspace currency are left out — the headline above already
  /// is that figure, and repeating it would say nothing.
  static String? _originals(
    List<CurrencyTotals> totals,
    String baseCurrency, {
    required bool opening,
  }) {
    final parts = <String>[
      for (final row in totals)
        if (row.currency != baseCurrency)
          if ((opening ? row.openingNetPosition : row.cashNetPosition) != 0)
            formatMoney(
              (opening ? row.openingNetPosition : row.cashNetPosition).abs(),
              currency: row.currency,
            ),
    ];
    if (parts.isEmpty) return null;
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final hasOpening =
        opening != null && (opening!.positionMinor != 0 || opening!.peopleCount > 0);

    // The per-currency breakdown behind each half (db/migrations/0024). Present
    // once the database has run 0024; before it, the card falls back to the
    // base-currency-only blocks.
    final cashRows = CurrencyHalfBreakdown.order(
      [for (final row in byCurrency) if (row.cash != null) row.cash!],
      baseCurrency,
    );
    final openingRows = CurrencyHalfBreakdown.order(
      [for (final row in byCurrency) if (row.opening != null) row.opening!],
      baseCurrency,
    );
    final hasBreakdown = cashRows.isNotEmpty;

    return SectionCard(
      title: 'Cash in hand',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              hasOpening
                  ? 'The regular trading position across every account, in the currency '
                      'each amount was entered in. The opening balances are counted '
                      'separately below and are not part of this figure.'
                  : 'The regular trading position across every account, in the currency '
                      'each amount was entered in.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.inkFaint),
            ),
          ),
          if (hasBreakdown) ...[
            for (final row in cashRows) ...[
              Divider(height: 1, color: palette.line),
              CurrencyHalfBlock(row: row, baseCurrency: baseCurrency, opening: false),
            ],
            _TotalLine(position: cash, currency: baseCurrency),
            if (hasOpening) ...[
              Divider(height: 1, color: palette.lineStrong),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OPENING BALANCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'What the accounts were carried in with, less whatever has been '
                      'settled against it. Independently calculated, never part of cash '
                      'in hand.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: palette.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              for (final row in openingRows) ...[
                Divider(height: 1, color: palette.line),
                CurrencyHalfBlock(row: row, baseCurrency: baseCurrency, opening: true),
              ],
              _TotalLine(position: opening!, currency: baseCurrency),
            ],
          ] else ...[
            _WorkspacePositionBlock(
              label: 'CASH IN HAND',
              position: cash,
              currency: baseCurrency,
              originals: _originals(byCurrency, baseCurrency, opening: false),
            ),
            if (hasOpening) ...[
              Divider(height: 1, color: palette.line),
              _WorkspacePositionBlock(
                label: 'OPENING BALANCE',
                position: opening!,
                currency: baseCurrency,
                originals: _originals(byCurrency, baseCurrency, opening: true),
                caption: 'What the accounts were carried in with, less whatever has '
                    'been settled against it. Independently calculated.',
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The consolidated figure for one half, in the workspace currency — shown once
/// beneath the per-currency blocks as the reference total. The only converted
/// number in the card; nothing settles against it.
class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.position, required this.currency});

  final WorkspacePosition position;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final net = position.positionMinor;
    final tone = net > 0
        ? palette.receivable
        : net < 0
            ? palette.payable
            : palette.inkMuted;

    return Container(
      color: context.colors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'TOTAL IN $currency',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: palette.inkFaint,
              ),
            ),
          ),
          Text(
            formatApprox(net.abs(), currency: currency),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two totals, with its own receivable / payable / settled / today.
class _WorkspacePositionBlock extends StatelessWidget {
  const _WorkspacePositionBlock({
    required this.label,
    required this.position,
    required this.currency,
    this.originals,
    this.caption,
  });

  final String label;
  final WorkspacePosition position;
  final String currency;

  /// The figures this total was converted from, in the currencies they were
  /// entered in. Null on a single-currency workspace, where the headline
  /// already is the original.
  final String? originals;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final net = position.positionMinor;
    final tone = net > 0
        ? palette.receivable
        : net < 0
            ? palette.payable
            : palette.inkMuted;

    Widget figure(String name, int minor, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
              ),
              const SizedBox(height: 1),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  minor,
                  currency: currency,
                  base: currency,
                  tone: MoneyTone.neutral,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: palette.inkFaint,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MoneyText(
              net.abs(),
              currency: currency,
              base: currency,
              tone: MoneyTone.neutral,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ),
          if (originals != null) ...[
            const SizedBox(height: 2),
            Text(
              'from $originals',
              style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: TextStyle(fontSize: 12, height: 1.4, color: palette.inkFaint),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              figure('Receivable', position.receivableMinor, palette.receivable),
              figure('Payable', position.payableMinor, palette.payable),
              figure('Settled', position.settledMinor, palette.inkMuted),
              figure('Today', position.todayMinor, palette.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
}


/// What moved today. Three small figures read faster than one line of prose
/// containing three figures — and it only appears on a day something happened.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.today, required this.currency});

  final TodayTotals today;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md - 1,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: palette.line),
      ),
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.date, size: AppIconSize.xs, color: palette.inkFaint),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                'TODAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: palette.inkFaint,
                ),
              ),
            ],
          ),
          // The engine's `credit` bucket is the owner-to-person direction, which
          // the product calls a debit — see docs/accounting-direction.md.
          if (today.credit > 0)
            _TodayFigure(
              icon: AppIcons.receivable,
              label: 'debited',
              minor: today.credit,
              currency: currency,
              color: palette.receivable,
            ),
          if (today.debit > 0)
            _TodayFigure(
              icon: AppIcons.payable,
              label: 'credited',
              minor: today.debit,
              currency: currency,
              color: palette.payable,
            ),
          if (today.settled > 0)
            _TodayFigure(
              icon: AppIcons.settlement,
              label: 'settled',
              minor: today.settled,
              currency: currency,
              color: palette.inkMuted,
            ),
        ],
      ),
    );
  }
}

class _TodayFigure extends StatelessWidget {
  const _TodayFigure({
    required this.icon,
    required this.label,
    required this.minor,
    required this.currency,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int minor;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.xs, color: color),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(
          formatMoney(minor, currency: currency, base: currency),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: AppSpacing.xs + 1),
        Text(label, style: TextStyle(fontSize: 12.5, color: context.money.inkFaint)),
      ],
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
    final palette = context.money;
    final meta = subtitle ??
        (person.lastActivityAt == null
            ? 'No activity yet'
            : friendlyDate(person.lastActivityAt!));

    return Column(
      children: [
        Hoverable(
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            color: hovered ? palette.sunken : Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/people/${person.personId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md - 1,
                ),
                child: Row(
                  children: [
                    Avatar(person.name, size: 40),
                    const SizedBox(width: AppSpacing.md),
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
                            style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    NetBadge(
                      netMinor: person.netBalance,
                      currency: person.currency,
                      base: currency,
                      approxMinor: person.netBalanceBase,
                      approxCurrency: person.baseCurrency,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedSlide(
                      duration: Motion.fast,
                      curve: Motion.enter,
                      offset: Offset(hovered ? 0.2 : 0, 0),
                      child: Icon(
                        AppIcons.forward,
                        size: AppIconSize.sm,
                        color: hovered ? palette.inkMuted : palette.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (divider)
          Divider(height: 1, color: palette.line, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
      ],
    );
  }
}

/// One activity entry. Shared by the dashboard, the activity screen and search
/// so the three never drift apart.
///
/// Direction is stated three ways at once — glyph, tinted plate and the word in
/// the meta line — because colour alone is not a statement anyone can rely on
/// (context.md §28).
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

    final icon = item.isSettlement
        ? AppIcons.settlement
        : item.isReceivable
            ? AppIcons.receivable
            : AppIcons.payable;

    // The row has three levels, not one grey string (upgrade §6): who, then
    // what kind of entry and when, then the note. Joining all of them with
    // middots made every row the same weight, so the eye had to read the whole
    // line to find the one word that distinguished it — and an opening balance
    // whose stored note is "Opening balance" printed the phrase twice.
    final note = item.note?.trim();
    final showNote = note != null && note.isNotEmpty && note != item.label;

    return Column(
      children: [
        Hoverable(
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            color: hovered ? palette.sunken : Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/people/${item.personId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md - 1,
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
                          Text(
                            item.personName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              // The type is set in neutral ink, not in the
                              // direction's colour. Three things were saying
                              // "which way" on every row — the tinted icon
                              // tile, this word, and the amount — and one of
                              // them said it confusingly: this ledger's `debit`
                              // is the receivable side, so a green word "Debit"
                              // reads as a contradiction to anyone who has not
                              // been told the convention (core/direction.dart).
                              // The tile and the amount carry direction; the
                              // word only names the entry. Matches the same
                              // change in web/src/components/ledger/activity-row.tsx.
                              Flexible(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: palette.inkMuted,
                                  ),
                                ),
                              ),
                              if (showDate) ...[
                                Text(
                                  ' · ',
                                  style: TextStyle(fontSize: 12.5, color: palette.inkSubtle),
                                ),
                                Flexible(
                                  child: Text(
                                    friendlyDate(item.entryDate),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (showNote) ...[
                            const SizedBox(height: 1),
                            Text(
                              note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: palette.inkMuted),
                            ),
                          ],
                          // The rate, third and quietest. It repeats neither
                          // figure on the right: it says what links them, and
                          // whether a human chose either of them (upgrade §45).
                          if (item.enteredCurrency != null) ...[
                            const SizedBox(height: 1),
                            RateNote(
                              enteredMinor: item.enteredAmountMinor,
                              enteredCurrency: item.enteredCurrency,
                              rateE9: item.exchangeRateE9,
                              rateSource: item.exchangeRateSource,
                              accountCurrency: item.currency,
                              conversionMode: item.conversionMode,
                              autoConvertedMinor: item.autoConvertedAmountMinor,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // What was ENTERED leads, in the currency it was entered
                    // in. `amountMinor` is the person's ledger denomination, so
                    // a USD 40 entry on a rupee account used to read ₹3,817.11
                    // here — the conversion talking over the fact. The base
                    // equivalent sits under it as what it is: supplementary.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoneyText(
                          item.entryAmountMinor,
                          currency: item.entryCurrency,
                          base: currency,
                          tone: item.isSettlement
                              ? MoneyTone.neutral
                              : item.isReceivable
                                  ? MoneyTone.receivable
                                  : MoneyTone.payable,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        if (item.showsBaseEquivalent)
                          Text(
                            formatApprox(item.amountBaseMinor!, currency: item.baseCurrency!),
                            style: TextStyle(fontSize: 11.5, color: palette.inkFaint),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (divider)
          Divider(height: 1, color: palette.line, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
      ],
    );
  }
}

/// The loading state, shaped like the screen it precedes so the transition to
/// real content is a change of contents rather than a change of layout.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          const Skeleton(width: 190, height: 24),
          const SizedBox(height: AppSpacing.sm),
          const Skeleton(width: 240, height: 13),
          const SizedBox(height: AppSpacing.lg),
        ],
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xl),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: 96, height: 11),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 200, height: 38),
                    SizedBox(height: AppSpacing.md),
                    Skeleton(width: 110, height: 13),
                  ],
                ),
              ),
              Divider(height: 1, color: context.money.line),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 2; i++) ...[
                      if (i == 1) VerticalDivider(width: 1, color: context.money.line),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? AppSpacing.lg : AppSpacing.xl,
                            vertical: AppSpacing.lg,
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton(width: 84, height: 12),
                              SizedBox(height: AppSpacing.sm),
                              Skeleton(width: 108, height: 22),
                              SizedBox(height: AppSpacing.sm),
                              Skeleton(width: 130, height: 11),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        const Card(child: SkeletonList(rows: 4)),
        const SizedBox(height: AppSpacing.lg),
        const Card(child: SkeletonList(rows: 3)),
      ],
    );
  }
}
