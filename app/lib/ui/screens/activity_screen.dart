import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../core/money.dart';
import '../motion.dart';
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Activity')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PageBody(
              child: Column(
                children: [
                  const _Totals(),
                  const SizedBox(height: 12),
                  SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Everything')),
                  ButtonSegment(value: 'transaction', label: Text('Transactions')),
                  ButtonSegment(value: 'settlement', label: Text('Settlements')),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (values) => setState(() {
                  _kind = values.first;
                  _page = 0;
                }),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(activityProvider),
              child: async.when(
                loading: () => const SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: PageBody(child: Card(child: SkeletonList(rows: 7))),
                ),
                error: (error, _) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ErrorNote('$error', onRetry: () => ref.invalidate(activityProvider)),
                  ],
                ),
                data: (activity) {
                  if (activity.items.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        PageBody(
                          child: Card(
                            child: EmptyState(
                              icon: Icons.timeline_outlined,
                              title: 'Nothing here yet',
                              description:
                                  'Transactions and settlements will appear here as you record them.',
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Weekday names inside the last week, dates beyond it —
                  // which is how people actually refer to recent days.
                  final groups = groupByDate(
                    activity.items,
                    (item) => item.entryDate,
                    label: dayGroupLabel,
                  );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: [
                      PageBody(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${activity.total} '
                              '${activity.total == 1 ? 'entry' : 'entries'} in this workspace',
                              style: TextStyle(fontSize: 12.5, color: context.money.inkFaint),
                            ),
                            const SizedBox(height: 12),

                            for (final (index, group) in groups.indexed) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: Row(
                                  children: [
                                    Text(
                                      group.label.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.6,
                                        color: context.money.inkFaint,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Divider(height: 1, color: context.money.line),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${group.items.length}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.money.inkFaint,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Reveal(
                                delay: Motion.stagger(index),
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      for (final item in group.items)
                                        ActivityRow(
                                          item: item,
                                          currency: currency,
                                          showDate: false,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],

                            if (_page > 0 || activity.hasMore)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed:
                                        _page > 0 ? () => setState(() => _page--) : null,
                                    child: const Text('← Newer'),
                                  ),
                                  TextButton(
                                    onPressed: activity.hasMore
                                        ? () => setState(() => _page++)
                                        : null,
                                    child: const Text('Older →'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
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
    final async = ref.watch(activitySummaryProvider);
    final buckets = async.valueOrNull;
    if (buckets == null || buckets.isEmpty) return const SizedBox.shrink();

    var credit = 0, debit = 0, settled = 0;
    for (final bucket in buckets) {
      credit += bucket.credit;
      debit += bucket.debit;
      settled += bucket.settled;
    }

    final palette = context.money;

    Widget cell(String label, String caption, int minor, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMinor(minor, currency: currency),
                    style: context.display(16).copyWith(color: color),
                  ),
                ),
                const SizedBox(height: 3),
                Text(caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.inkFaint)),
              ],
            ),
          ),
        );

    return SectionCard(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell('Credit', 'They gave you', debit, palette.payable),
            VerticalDivider(width: 1, color: palette.line),
            cell('Debit', 'You gave them', credit, palette.receivable),
            VerticalDivider(width: 1, color: palette.line),
            cell('Settled', 'Either way', settled, context.colors.onSurface),
          ],
        ),
      ),
    );
  }
}
