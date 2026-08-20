import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../motion.dart';
import '../sheets/person_sheet.dart';
import '../widgets/common.dart';

/// People — the account directory (context.md §5).
///
/// Scannable in one pass: who, how much, which way. The totals strip above the
/// list is the same figure the dashboard shows, so arriving here from there is
/// continuous rather than a context switch.
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
  _Side _side = _Side.all;

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

  /// The direction filter applied over the rows the query already returned.
  List<PersonBalance> _apply(List<PersonBalance> people) =>
      people.where((person) => _side.matches(person.netBalance)).toList();

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
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final side in _Side.values) ...[
                          _SideChip(
                            label: side.label,
                            selected: _side == side,
                            onTap: () => setState(() => _side = side),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
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
                    ErrorNote.forError(error, onRetry: () => ref.invalidate(peopleProvider)),
                  ],
                ),
                data: (all) => _apply(all).isEmpty
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
                                  : _side != _Side.all
                                      ? EmptyState(
                                          icon: Icons.filter_list_off,
                                          title: 'Nothing in this filter',
                                          description: switch (_side) {
                                            _Side.receivable => 'No one currently owes you.',
                                            _Side.payable =>
                                              'You do not currently owe anyone.',
                                            _ => 'No accounts are fully settled.',
                                          },
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
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                        children: [
                          PageBody(
                            child: Column(
                              children: [
                                _Totals(people: all, currency: currency),
                                const SizedBox(height: 12),
                                Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Stagger(
                                    children: [
                                      for (final person in _apply(all))
                                        _PersonTile(person: person, currency: currency),
                                    ],
                                  ),
                                ),
                              ],
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
        InkWell(
          onTap: () => context.push('/people/${person.personId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Avatar(person.name, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (person.isArchived) ...[
                            const SizedBox(width: 8),
                            const StatusChip('Archived', tone: StatusTone.muted),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _meta(person),
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
        Divider(height: 1, color: context.money.line, indent: 16, endIndent: 16),
      ],
    );
  }
}


/// The direction filter. A view over the rows already fetched, so switching it
/// costs no round trip and the totals above still describe the whole workspace.
enum _Side {
  all,
  receivable,
  payable,
  settled;

  String get label => switch (this) {
        _Side.all => 'All',
        _Side.receivable => 'Receivable',
        _Side.payable => 'Payable',
        _Side.settled => 'Settled',
      };

  bool matches(int netMinor) => switch (this) {
        _Side.all => true,
        _Side.receivable => balanceTone(netMinor) == BalanceTone.receivable,
        _Side.payable => balanceTone(netMinor) == BalanceTone.payable,
        _Side.settled => balanceTone(netMinor) == BalanceTone.settled,
      };
}

class _SideChip extends StatelessWidget {
  const _SideChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    return AnimatedContainer(
      duration: Motion.micro,
      curve: Motion.enter,
      decoration: BoxDecoration(
        color: selected ? palette.accentSoft : palette.sunken,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: selected ? palette.accentLine : palette.line),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? context.colors.primary : palette.inkMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the whole workspace adds up to, above the list it describes.
class _Totals extends StatelessWidget {
  const _Totals({required this.people, required this.currency});

  final List<PersonBalance> people;
  final String currency;

  @override
  Widget build(BuildContext context) {
    var receivable = 0;
    var payable = 0;
    for (final person in people) {
      if (person.netBalance > 0) receivable += person.netBalance;
      if (person.netBalance < 0) payable += -person.netBalance;
    }
    if (receivable == 0 && payable == 0) return const SizedBox.shrink();

    final palette = context.money;

    Widget figure(String label, int minor, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: palette.inkMuted)),
            const SizedBox(height: 3),
            Text(
              formatMinor(minor, currency: currency),
              style: context.display(17).copyWith(color: color),
            ),
          ],
        );

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              figure('Owed to you', receivable, palette.receivable),
              const SizedBox(width: 26),
              figure('You owe', payable, palette.payable),
            ],
          ),
          const SizedBox(height: 12),
          SplitBar(receivable: receivable, payable: payable),
        ],
      ),
    );
  }
}

String _meta(PersonBalance person) {
  if (person.lastActivityAt != null) {
    final when = friendlyDate(person.lastActivityAt!);
    return person.phone == null ? when : '${person.phone} · $when';
  }
  return person.phone ??
      (person.transactionCount == 0
          ? 'No transactions yet'
          : '${person.transactionCount} '
              '${person.transactionCount == 1 ? 'transaction' : 'transactions'}');
}
