import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../providers.dart';
import 'screens/search_sheet.dart';
import 'sheets/transaction_sheet.dart';
import 'widgets/common.dart';

/// Adaptive shell (context.md §29).
///
/// The breakpoint is width, not platform: a Windows window narrowed to phone
/// width gets the bottom bar, and an Android tablet in landscape gets the rail.
/// One rule, no `Platform.isX` anywhere.
const double kWideBreakpoint = 900;

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    (path: '/', label: 'Dashboard', icon: Icons.dashboard_outlined, active: Icons.dashboard),
    (path: '/people', label: 'People', icon: Icons.people_outline, active: Icons.people),
    (path: '/activity', label: 'Activity', icon: Icons.timeline_outlined, active: Icons.timeline),
    (path: '/profile', label: 'Profile', icon: Icons.person_outline, active: Icons.person),
  ];

  int get _index {
    final match = _destinations.indexWhere(
      (d) => d.path == '/' ? location == '/' : location.startsWith(d.path),
    );
    return match < 0 ? 0 : match;
  }

  void _go(BuildContext context, int index) => context.go(_destinations[index].path);

  Future<void> _addTransaction(BuildContext context, WidgetRef ref) async {
    final saved = await showTransactionSheet(context, ref);
    if (saved && context.mounted) {
      showMessage(context, 'Transaction saved.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;
    final me = ref.watch(meProvider).valueOrNull;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(
              index: _index,
              destinations: _destinations,
              onSelect: (index) => _go(context, index),
              onSearch: () => showSearchSheet(context, ref),
              onAdd: () => _addTransaction(context, ref),
              name: me?.name ?? '',
              subtitle: me?.businessName ?? me?.email ?? '',
            ),
            VerticalDivider(width: 1, color: context.money.line),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => _go(context, index),
        destinations: [
          for (final (i, destination) in _destinations.indexed)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.active),
              label: destination.label,
              tooltip: destination.label,
              // The index is only used to pick the filled icon; kept explicit
              // so the analyzer does not flag the unused loop variable.
              key: ValueKey('nav-$i'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTransaction(context, ref),
        tooltip: 'Add transaction',
        elevation: 2,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.destinations,
    required this.onSelect,
    required this.onSearch,
    required this.onAdd,
    required this.name,
    required this.subtitle,
  });

  final int index;
  final List<({String path, String label, IconData icon, IconData active})> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      color: context.colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 17,
                      color: context.colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Ledger',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Search'),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  alignment: Alignment.centerLeft,
                  foregroundColor: context.money.inkMuted,
                  backgroundColor: context.money.sunken,
                ),
              ),
            ),

            const SizedBox(height: 14),

            for (final (i, destination) in destinations.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: _RailItem(
                  label: destination.label,
                  icon: i == index ? destination.active : destination.icon,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add transaction'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              ),
            ),

            Divider(height: 1, color: context.money.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: context.money.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? context.colors.primary : context.money.inkMuted,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? context.colors.primary : context.money.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
