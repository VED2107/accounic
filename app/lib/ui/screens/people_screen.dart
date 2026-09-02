import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/ledger_repository.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../motion.dart';
import '../sheets/person_sheet.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';

/// People — the account directory (context.md §5).
///
/// A relationship manager rather than a table: who, how much, which way, and
/// when it last moved. The totals strip above the list is the same figure the
/// dashboard shows, so arriving here from there is continuous rather than a
/// context switch.
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

  /// The direction filter, applied over the rows the query already returned.
  /// A view rather than a second request: switching it costs no round trip, and
  /// the totals above still describe the whole workspace.
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

    final all = async.valueOrNull ?? const <PersonBalance>[];
    final shown = _apply(all);

    return AppPage(
      title: 'People',
      subtitle: async.hasValue
          ? '${all.length} ${all.length == 1 ? 'account' : 'accounts'} on your ledger'
          : null,
      width: ContentWidth.standard,
      bottomPadding: context.isCompact ? 120 : 48,
      actions: [
        AppIconAction(
          icon: AppIcons.addPerson,
          tooltip: 'Add person',
          onPressed: _addPerson,
          emphasised: true,
        ),
      ],
      toolbar: _Toolbar(
        controller: _search,
        onChanged: _onSearchChanged,
        onClear: () {
          _search.clear();
          setState(() => _query = '');
        },
        side: _side,
        onSide: (side) => setState(() => _side = side),
        sort: _sort,
        onSort: (sort) => setState(() => _sort = sort),
        includeArchived: _includeArchived,
        onArchived: () => setState(() => _includeArchived = !_includeArchived),
      ),
      onRefresh: () async => ref.invalidate(peopleProvider),
      children: switch (async) {
        AsyncError(:final error) => [
            ErrorNote.forError(
              error,
              what: 'your people',
              onRetry: () => ref.invalidate(peopleProvider),
            ),
          ],
        AsyncData() when shown.isEmpty => [_emptyState()],
        AsyncData() => [
            if (_side == _Side.all) ...[
              Reveal(child: _Totals(people: all, currency: currency)),
              const SizedBox(height: AppSpacing.lg),
            ],
            Reveal(
              delay: const Duration(milliseconds: 40),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Stagger(
                  children: [
                    for (final (index, person) in shown.indexed)
                      _PersonTile(
                        person: person,
                        currency: currency,
                        divider: index < shown.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ],
        _ => const [
            Card(child: SkeletonList(rows: 8)),
          ],
      },
    );
  }

  Widget _emptyState() {
    if (_query.isNotEmpty) {
      return Card(
        child: EmptyState(
          icon: AppIcons.noResults,
          title: 'Nothing matches “$_query”',
          description: 'Try a different name or phone number.',
        ),
      );
    }

    if (_side != _Side.all) {
      return Card(
        child: EmptyState(
          icon: AppIcons.noFilterMatch,
          title: 'Nothing in this filter',
          description: switch (_side) {
            _Side.receivable => 'No one currently owes you.',
            _Side.payable => 'You do not currently owe anyone.',
            _ => 'No accounts are fully settled.',
          },
          action: TextButton(
            onPressed: () => setState(() => _side = _Side.all),
            child: const Text('Show everyone'),
          ),
        ),
      );
    }

    return Card(
      child: EmptyState(
        icon: AppIcons.noPeople,
        title: 'No one is on your ledger yet',
        description: 'Add your first person or business to start tracking money.',
        action: FilledButton.icon(
          onPressed: _addPerson,
          icon: const Icon(AppIcons.addPerson, size: AppIconSize.sm),
          label: const Text('Add person'),
        ),
      ),
    );
  }
}

/// Search, direction, sort, archived — on one line where there is room for it
/// and on two where there is not.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.side,
    required this.onSide,
    required this.sort,
    required this.onSort,
    required this.includeArchived,
    required this.onArchived,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final _Side side;
  final ValueChanged<_Side> onSide;
  final PeopleSort sort;
  final ValueChanged<PeopleSort> onSort;
  final bool includeArchived;
  final VoidCallback onArchived;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    final search = TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search name or phone',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.sm),
          child: Icon(AppIcons.search, size: AppIconSize.sm, color: palette.inkFaint),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(AppIcons.close, size: AppIconSize.sm, color: palette.inkFaint),
                onPressed: onClear,
                splashRadius: 18,
              ),
      ),
    );

    final filters = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in _Side.values) ...[
                  _Chip(
                    label: value.label,
                    selected: side == value,
                    onTap: () => onSide(value),
                  ),
                  const SizedBox(width: AppSpacing.sm - 2),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _SortMenu(sort: sort, onSort: onSort),
        const SizedBox(width: AppSpacing.sm - 2),
        _ArchivedToggle(on: includeArchived, onTap: onArchived),
      ],
    );

    if (context.isCompact) {
      return Column(
        children: [
          search,
          const SizedBox(height: AppSpacing.md - 2),
          filters,
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 300, child: search),
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: filters),
      ],
    );
  }
}

/// The direction filter chip.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.enter,
        height: 34,
        decoration: BoxDecoration(
          color: selected
              ? palette.accentSoft
              : hovered
                  ? palette.raised
                  : palette.sunken,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected
                ? palette.accentLine
                : hovered
                    ? palette.lineStrong
                    : palette.line,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg - 2),
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
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onSort});

  final PeopleSort sort;
  final ValueChanged<PeopleSort> onSort;

  static const _labels = {
    PeopleSort.name: 'Name',
    PeopleSort.balance: 'Balance',
    PeopleSort.recent: 'Recent',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) => PopupMenuButton<PeopleSort>(
        tooltip: 'Sort',
        position: PopupMenuPosition.under,
        color: palette.raised,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.fieldAll,
          side: BorderSide(color: palette.lineStrong),
        ),
        onSelected: onSort,
        itemBuilder: (context) => [
          for (final entry in _labels.entries)
            PopupMenuItem(
              value: entry.key,
              child: Row(
                children: [
                  Icon(
                    AppIcons.check,
                    size: AppIconSize.sm,
                    color: sort == entry.key ? context.colors.primary : Colors.transparent,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(entry.value, style: const TextStyle(fontSize: 13.5)),
                ],
              ),
            ),
        ],
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: hovered ? palette.raised : palette.sunken,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: hovered ? palette.lineStrong : palette.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _labels[sort]!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: palette.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 1),
              Icon(AppIcons.expand, size: AppIconSize.xs, color: palette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArchivedToggle extends StatelessWidget {
  const _ArchivedToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Tooltip(
      message: on ? 'Hide archived accounts' : 'Show archived accounts',
      child: Hoverable(
        builder: (context, hovered) => Pressable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? palette.accentSoft
                  : hovered
                      ? palette.raised
                      : palette.sunken,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(
                color: on
                    ? palette.accentLine
                    : hovered
                        ? palette.lineStrong
                        : palette.line,
              ),
            ),
            child: Icon(
              AppIcons.archive,
              size: AppIconSize.sm,
              color: on ? context.colors.primary : palette.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.currency,
    required this.divider,
  });

  final PersonBalance person;
  final String currency;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Column(
      children: [
        Hoverable(
          builder: (context, hovered) => HoverFill(
            color: hovered ? palette.sunken : Colors.transparent,
            child: InkWell(
              onTap: () => context.push('/people/${person.personId}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Opacity(
                      opacity: person.isArchived ? 0.55 : 1,
                      child: Avatar(person.name, size: 42),
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
                                const SizedBox(width: AppSpacing.sm),
                                const StatusChip('Archived', tone: StatusTone.muted),
                              ],
                            ],
                          ),
                          if (_metaWhen(person) != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              _metaWhen(person)!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: palette.inkMuted),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              // The account's own currency, when it is not the
                              // workspace's. A multi-currency directory where a
                              // row does not say what it is denominated in is a
                              // directory you have to open to read (upgrade 42).
                              if (person.currency != person.baseCurrency) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.sunken,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: palette.lineStrong),
                                  ),
                                  child: Text(
                                    person.currency,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: palette.inkMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                              ],
                              Flexible(
                                child: Text(
                                  _metaDetail(person),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: palette.inkFaint),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // Each account is shown in its own currency; the totals
                    // at the top are the only converted figures here.
                    NetBadge(
                      netMinor: person.netBalance,
                      currency: person.currency,
                      base: currency,
                      approxMinor: person.netBalanceBase,
                      approxCurrency: person.baseCurrency,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    HoverSlide(
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

/// The direction filter.
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

    Widget figure(String label, IconData icon, int minor, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                child: AnimatedMoney(
                  minor,
                  currency: currency,
                  style: context.display(20),
                ),
              ),
            ],
          ),
        );

    return SectionCard(
      padding: EdgeInsets.symmetric(
        horizontal: context.isCompact ? AppSpacing.lg : AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              figure('Owed to you', AppIcons.receivable, receivable, palette.receivable),
              const SizedBox(width: AppSpacing.xxl),
              figure('You owe', AppIcons.payable, payable, palette.payable),
            ],
          ),
          const SizedBox(height: AppSpacing.md + 2),
          SplitBar(receivable: receivable, payable: payable),
        ],
      ),
    );
  }
}

/// When the account last moved — the line a directory is scanned by.
///
/// Split from [_metaDetail] because the row used to show the last activity date
/// OR the transaction count, whichever happened to be available, so an active
/// account never said how much history was behind it and a dormant one never
/// said when it went quiet. They answer different questions. Matches the same
/// change in web/src/app/(app)/people/page.tsx.
String? _metaWhen(PersonBalance person) {
  if (person.lastActivityAt == null) return null;
  return 'Last activity ${friendlyDate(person.lastActivityAt!)}';
}

/// How much history, and how to reach them. One step quieter again.
String _metaDetail(PersonBalance person) {
  final count = person.transactionCount == 0
      ? 'No transactions yet'
      : '${person.transactionCount} '
          '${person.transactionCount == 1 ? 'transaction' : 'transactions'}';
  return person.phone == null ? count : '$count · ${person.phone}';
}
