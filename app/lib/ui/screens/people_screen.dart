import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../sheets/person_sheet.dart';
import '../widgets/common.dart';

/// People list (context.md §5).
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _includeArchived = false;
  PeopleSort _sort = PeopleSort.name;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounced so typing does not fire a query per keystroke (context.md §23).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _addPerson() async {
    final person = await showPersonSheet(context, ref);
    if (person != null && mounted) {
      // Straight to the new account: the reason to add someone is almost always
      // to record something against them (context.md §36).
      context.push('/people/${person.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final async = ref.watch(peopleProvider(
      (query: _query, includeArchived: _includeArchived, sort: _sort),
    ));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            onPressed: _addPerson,
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Add person',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PageBody(
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search name or phone',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<PeopleSort>(
                          segments: const [
                            ButtonSegment(value: PeopleSort.name, label: Text('Name')),
                            ButtonSegment(value: PeopleSort.balance, label: Text('Balance')),
                            ButtonSegment(value: PeopleSort.recent, label: Text('Recent')),
                          ],
                          selected: {_sort},
                          showSelectedIcon: false,
                          onSelectionChanged: (values) =>
                              setState(() => _sort = values.first),
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            textStyle: WidgetStatePropertyAll(
                              TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: () =>
                            setState(() => _includeArchived = !_includeArchived),
                        isSelected: _includeArchived,
                        tooltip: _includeArchived ? 'Hide archived' : 'Show archived',
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(peopleProvider),
              child: async.when(
                loading: () => const SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: PageBody(child: Card(child: SkeletonList(rows: 7))),
                ),
                error: (error, _) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ErrorNote('$error', onRetry: () => ref.invalidate(peopleProvider)),
                  ],
                ),
                data: (people) => people.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          PageBody(
                            child: Card(
                              child: _query.isNotEmpty
                                  ? EmptyState(
                                      icon: Icons.search_off,
                                      title: 'Nothing matches “$_query”',
                                      description: 'Try a different name or phone number.',
                                    )
                                  : EmptyState(
                                      icon: Icons.people_outline,
                                      title: 'No people yet',
                                      description:
                                          'Add your first person or business to start tracking money.',
                                      action: FilledButton.icon(
                                        onPressed: _addPerson,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add person'),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: [
                          PageBody(
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (final person in people)
                                    _PersonTile(person: person, currency: currency),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, required this.currency});

  final PersonBalance person;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: () => context.push('/people/${person.personId}'),
          leading: Avatar(person.name),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              if (person.isArchived) ...[
                const SizedBox(width: 8),
                const StatusChip('Archived', tone: StatusTone.muted),
              ],
            ],
          ),
          subtitle: Text(
            person.phone ??
                (person.transactionCount == 0
                    ? 'No transactions yet'
                    : '${person.transactionCount} '
                        '${person.transactionCount == 1 ? 'transaction' : 'transactions'}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: NetBadge(netMinor: person.netBalance, currency: currency),
        ),
        Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}
