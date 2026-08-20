import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart' show ActivityRow;

/// Workspace activity (context.md §16, §30).
///
/// Everything that happened, newest first, filterable to transactions or
/// settlements, paginated because a long-running ledger is not a small list
/// (context.md §23).
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
              child: SegmentedButton<String?>(
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

                  final groups = groupByDate(activity.items, (item) => item.entryDate);

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

                            for (final group in groups) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
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
                                    for (final item in group.items)
                                      ActivityRow(item: item, currency: currency),
                                  ],
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
