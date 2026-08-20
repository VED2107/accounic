import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/icons.dart';
import '../core/layout.dart';
import '../core/theme.dart';
import '../providers.dart';
import 'motion.dart';
import 'screens/search_sheet.dart';
import 'sheets/transaction_sheet.dart';
import 'widgets/brand.dart';
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

  // Lucide has one weight, not an outline/filled pair, so a selected
  // destination is marked by colour and by the plate behind it rather than by
  // swapping the glyph. That is the more honest signal anyway: a filled icon
  // says "a different thing", where a tinted one says "you are here".
  static const _destinations = [
    (path: '/', label: 'Dashboard', icon: AppIcons.dashboard),
    (path: '/people', label: 'People', icon: AppIcons.people),
    (path: '/activity', label: 'Activity', icon: AppIcons.activity),
    (path: '/profile', label: 'Profile', icon: AppIcons.profile),
  ];

  /// Administration is a rail destination, never a bottom-bar one: four thumb
  /// targets plus the primary action is already the width of a phone, and an
  /// admin reaches it from the profile screen there instead.
  static const _adminDestination = (
    path: '/admin',
    label: 'Administration',
    icon: AppIcons.admin,
  );

  int _indexIn(List<({String path, String label, IconData icon})> list) {
    final match = list.indexWhere(
      (d) => d.path == '/' ? location == '/' : location.startsWith(d.path),
    );
    return match < 0 ? 0 : match;
  }

  Future<void> _addTransaction(BuildContext context, WidgetRef ref) async {
    final saved = await showTransactionSheet(context, ref);
    if (saved && context.mounted) showMessage(context, 'Transaction recorded.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same threshold the layout system uses, so the rail and the in-page
    // header appear together rather than one width apart.
    final wide = context.isWide;
    final me = ref.watch(meProvider).valueOrNull;

    final railDestinations = [
      ..._destinations,
      if (me?.isAdmin ?? false) _adminDestination,
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(
              index: _indexIn(railDestinations),
              destinations: railDestinations,
              onSelect: (index) => context.go(railDestinations[index].path),
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
      extendBody: true,
      bottomNavigationBar: _BottomBar(
        index: _indexIn(_destinations),
        destinations: _destinations,
        onSelect: (index) => context.go(_destinations[index].path),
      ),
      // Docked into the gap the bar leaves for it, overlapping its top edge:
      // the strongest element on the screen, in the same place on every screen.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AddTransactionButton(
        onTap: () => _addTransaction(context, ref),
      ),
    );
  }
}

/// The phone's navigation: four destinations with the primary action sitting in
/// the middle of them, lifted proud of the bar.
///
/// A real FloatingActionButton would either float over content or need the bar
/// notched around it; this is laid out as part of the bar, so it cannot collide
/// with anything and the thumb finds it in the same place on every screen.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });

  final int index;
  final List<({String path, String label, IconData icon})> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                destination: destinations[0],
                selected: index == 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                destination: destinations[1],
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              const SizedBox(width: 72),
              _NavItem(
                destination: destinations[2],
                selected: index == 2,
                onTap: () => onSelect(2),
              ),
              _NavItem(
                destination: destinations[3],
                selected: index == 3,
                onTap: () => onSelect(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary action. Lives in the shell's stack rather than the bar so it can
/// overlap the bar's top edge.
class AddTransactionButton extends StatelessWidget {
  const AddTransactionButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add transaction',
      child: Pressable(
        onTap: onTap,
        scale: 0.94,
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AccounicColors.actionGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.42),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(AppIcons.add, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({String path, String label, IconData icon}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.primary : context.money.inkFaint;

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The selected destination gets a tinted plate behind its glyph
              // rather than a heavier glyph. It reads at a glance without the
              // icon changing shape under the thumb.
              AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.enter,
                width: 44,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? context.money.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(destination.icon, size: AppIconSize.md + 1, color: color),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: Motion.micro,
                curve: Motion.enter,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
                child: Text(destination.label),
              ),
            ],
          ),
        ),
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
  final List<({String path, String label, IconData icon})> destinations;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onAdd;
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 244,
      color: context.colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: Align(alignment: Alignment.centerLeft, child: AccounicLogo()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                onPressed: onSearch,
                icon: const Icon(AppIcons.search, size: AppIconSize.sm),
                label: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Search'),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  alignment: Alignment.centerLeft,
                  foregroundColor: context.money.inkMuted,
                  side: BorderSide(color: context.money.line),
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final (i, destination) in destinations.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: _RailItem(
                  label: destination.label,
                  icon: destination.icon,
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Pressable(
                onTap: onAdd,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AccounicColors.actionGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusField),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.add, size: AppIconSize.md, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Add transaction',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: context.money.sunken,
                  borderRadius: BorderRadius.circular(AppTheme.radiusField),
                  border: Border.all(color: context.money.line),
                ),
                child: Row(
                  children: [
                    Avatar(name.isEmpty ? '?' : name, size: 32, tone: AvatarTone.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: context.money.inkFaint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
    final palette = context.money;

    return Hoverable(
      builder: (context, hovered) {
        // Three states, not two: resting, pointed at, and current. Hover on an
        // unselected item borrows the selected item's surface but not its ink,
        // so it can never be mistaken for where you already are.
        final color = selected
            ? context.colors.primary
            : hovered
                ? context.colors.onSurface
                : palette.inkMuted;

        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          decoration: BoxDecoration(
            color: selected
                ? palette.accentSoft
                : hovered
                    ? palette.sunken
                    : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            border: Border.all(
              color: selected ? palette.accentLine : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.fieldAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md - 2,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: AppIconSize.md, color: color),
                    const SizedBox(width: AppSpacing.md - 1),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
