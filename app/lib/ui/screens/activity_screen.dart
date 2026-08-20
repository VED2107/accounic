import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart' show ActivityRow;

/// Workspace activity (context.md §16, §30).
///
/// A financial timeline, not a table: everything that happened, newest first,
/// grouped by the day it happened on and headed the way a person would say the
/// date out loud. Paginated, because a long-running ledger is not a small list
/// (context.md §23).
///
/// The three totals at the top are the whole of v1 reporting — the spec is
/// explicit that a reporting engine is not wanted yet.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int _page = 0;
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final async = ref.watch(activityProvider((page: _page, kind: _kind)));
    final total = async.valueOrNull?.total;

    return AppPage(
      title: 'Activity',
      subtitle: total == null
          ? null
          : '$total ${total == 1 ? 'entry' : 'entries'} in this workspace',
      width: ContentWidth.standard,
      bottomPadding: context.isCompact ? 120 : 48,
      // Capped rather than stretched: three words do not need 880px, and a
      // control as wide as the list below it competes with the list.
      toolbar: SizedBox(
        width: 420,
        child: Segmented<String?>(
          value: _kind,
          segments: const [
            (value: null, label: 'Everything'),
            (value: 'transaction', label: 'Transactions'),
            (value: 'settlement', label: 'Settlements'),
          ],
          onChanged: (value) => setState(() {
            _kind = value;
            _page = 0;
          }),
        ),
      ),
      onRefresh: () async => ref.invalidate(activityProvider),
      children: [
        const _Totals(),
        const SizedBox(height: AppSpacing.lg),

        // Switching tabs replaces the whole list, so it cross-fades as one
        // thing. Animating each row instead would read as the list rebuilding
        // rather than as the filter changing.
        AnimatedSwitcher(
          duration: Motion.normal,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(
            key: ValueKey('$_kind/$_page/${async.hasValue}/${async.hasError}'),
            child: switch (async) {
              AsyncError(:final error) => ErrorNote.forError(
                  error,
                  onRetry: () => ref.invalidate(activityProvider),
                ),
              AsyncData(:final value) when value.items.isEmpty => Card(
                  child: EmptyState(
                    icon: AppIcons.quiet,
                    title: switch (_kind) {
                      'settlement' => 'No settlements recorded yet',
                      'transaction' => 'No transactions recorded yet',
                      _ => 'Your ledger is quiet',
                    },
                    description: switch (_kind) {
                      'settlement' =>
                        'Settling an outstanding amount will show it here.',
                      'transaction' =>
                        'Record a credit or a debit and it will appear here.',
                      _ =>
                        'Transactions and settlements will appear here as you record them.',
                    },
                  ),
                ),
              AsyncData(:final value) => _Timeline(
                  activity: value,
                  currency: currency,
                  page: _page,
                  onPage: (page) => setState(() => _page = page),
                ),
              _ => const Card(child: SkeletonList(rows: 8)),
            },
          ),
        ),
      ],
    );
  }
}

/// The entries, grouped by day.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.activity,
    required this.currency,
    required this.page,
    required this.onPage,
  });

  final ActivityPage activity;
  final String currency;
  final int page;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    // Weekday names inside the last week, dates beyond it — which is how people
    // actually refer to recent days.
    final groups = groupByDate(
      activity.items,
      (item) => item.entryDate,
      label: dayGroupLabel,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                      for (final (row, item) in group.items.indexed)
                        ActivityRow(
                          item: item,
                          currency: currency,
                          showDate: false,
                          divider: row < group.items.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (page > 0 || activity.hasMore) ...[
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PageButton(
                label: 'Newer',
                icon: AppIcons.back,
                leading: true,
                onTap: page > 0 ? () => onPage(page - 1) : null,
              ),
              Text(
                'Page ${page + 1}',
                style: TextStyle(fontSize: 12.5, color: context.money.inkFaint),
              ),
              _PageButton(
                label: 'Older',
                icon: AppIcons.forward,
                leading: false,
                onTap: activity.hasMore ? () => onPage(page + 1) : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.label,
    required this.icon,
    required this.leading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final enabled = onTap != null;

    return Hoverable(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg - 2),
          decoration: BoxDecoration(
            color: hovered && enabled ? palette.raised : palette.sunken,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(color: hovered && enabled ? palette.lineStrong : palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading) ...[
                Icon(
                  icon,
                  size: AppIconSize.xs,
                  color: enabled ? palette.inkMuted : palette.inkFaint,
                ),
                const SizedBox(width: AppSpacing.sm - 2),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled ? palette.inkMuted : palette.inkFaint,
                ),
              ),
              if (!leading) ...[
                const SizedBox(width: AppSpacing.sm - 2),
                Icon(
                  icon,
                  size: AppIconSize.xs,
                  color: enabled ? palette.inkMuted : palette.inkFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Credit, debit and settled over the last thirty days.
///
/// Credit is what people gave the owner — the payable side — and the engine's
/// `credit` bucket counts the other direction, so the two are crossed over here
/// deliberately. See docs/accounting-direction.md.
class _Totals extends ConsumerWidget {
  const _Totals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final buckets = ref.watch(activitySummaryProvider).valueOrNull;
    if (buckets == null || buckets.isEmpty) return const SizedBox.shrink();

    var credit = 0, debit = 0, settled = 0;
    for (final bucket in buckets) {
      credit += bucket.credit;
      debit += bucket.debit;
      settled += bucket.settled;
    }

    final palette = context.money;

    Widget cell(String label, String caption, IconData icon, int minor, Color color) =>
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.isCompact ? AppSpacing.md + 2 : AppSpacing.lg,
              vertical: AppSpacing.md + 2,
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
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMinor(minor, currency: currency),
                    style: context.display(17),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.inkFaint),
                ),
              ],
            ),
          ),
        );

    return SectionCard(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell('Credit', 'They gave you', AppIcons.payable, debit, palette.payable),
            VerticalDivider(width: 1, color: palette.line),
            cell('Debit', 'You gave them', AppIcons.receivable, credit, palette.receivable),
            VerticalDivider(width: 1, color: palette.line),
            cell('Settled', 'Either way', AppIcons.settlement, settled, palette.inkMuted),
          ],
        ),
      ),
    );
  }
}
