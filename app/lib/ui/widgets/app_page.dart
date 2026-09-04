import 'package:flutter/material.dart';

import 'brand.dart';

import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';

/// The chrome every screen wears (context.md §18, §29).
///
/// Before this existed each screen built its own `Scaffold`, its own app bar and
/// its own centred column, and the widths drifted: one page capped its content
/// at 620px and the next at 1000px, so moving between them shifted the whole
/// layout sideways. Worse, two screens carried both an app-bar title *and* an
/// in-body headline, which read as two competing page titles.
///
/// So there is exactly one page title, and where it sits depends on the width:
///
/// * **Compact** — a short app bar, the way a phone does it. Titles are small
///   and out of the way; the content is what the thumb is here for.
/// * **Wide** — no app bar at all. The title is a proper editorial header
///   inside the page, set in the display face, with its actions on the same
///   optical line and a hairline under the whole block.
///
/// The header and the toolbar are fixed; only the content scrolls beneath them.
/// A page title that scrolls away is a website's idea, not an application's.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.compactTitle,
    this.actions = const [],
    this.leading,
    this.toolbar,
    this.onRefresh,
    this.width = ContentWidth.standard,
    this.bottomPadding = 32,
    this.scrollController,
    this.brandTitle = false,
  });

  final String title;

  /// Paint the wide header's title with the brand ramp.
  ///
  /// Set on the dashboard only. It is the one screen whose title is the
  /// product greeting rather than a noun, and the one place a gradient reads as
  /// identity rather than decoration.
  final bool brandTitle;

  /// The page itself. Laid out as one centred, width-capped column.
  final List<Widget> children;

  /// One line under the title on a wide window, explaining what the page is
  /// for. Dropped on a phone, where it would cost a third of the first screen.
  final String? subtitle;

  /// Replaces the app-bar title on a phone. The dashboard uses it to fly the
  /// brand where a wide window flies a greeting — a phone app bar is too short
  /// a line for "Good afternoon, Ved".
  final Widget? compactTitle;

  final List<Widget> actions;
  final Widget? leading;

  /// Filters, search, segmented controls: pinned under the header so the list
  /// scrolls beneath its own controls rather than away from them.
  final Widget? toolbar;

  final Future<void> Function()? onRefresh;
  final ContentWidth width;
  final double bottomPadding;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final gutter = context.gutter;

    // One child holding a Column of everything is a ListView that is not a
    // ListView: a single item is always in view, so every section on the page
    // is built, laid out and kept alive whether or not it is anywhere near the
    // screen. Handing the sections over individually is what makes the viewport
    // do its job.
    Widget content = ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(gutter, compact ? AppSpacing.sm : AppSpacing.lg, gutter,
          bottomPadding + MediaQuery.paddingOf(context).bottom),
      itemCount: children.length,
      itemBuilder: (context, index) => _Constrain(
        width: width,
        child: children[index],
      ),
    );

    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        edgeOffset: 4,
        color: context.colors.primary,
        backgroundColor: context.money.raised,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: compact
          ? AppBar(
              titleSpacing: leading == null ? gutter : 0,
              leading: leading,
              automaticallyImplyLeading: leading != null,
              title: compactTitle ?? Text(title),
              actions: [...actions, SizedBox(width: gutter - AppSpacing.sm)],
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            _WideHeader(
              title: title,
              subtitle: subtitle,
              actions: actions,
              leading: leading,
              width: width,
              gutter: gutter,
              brandTitle: brandTitle,
            ),
          if (toolbar != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                compact ? AppSpacing.md : AppSpacing.lg,
                gutter,
                AppSpacing.md,
              ),
              child: _Constrain(width: width, child: toolbar!),
            ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// The desktop page header. Title, one explanatory line, actions, hairline.
class _WideHeader extends StatelessWidget {
  const _WideHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.leading,
    required this.width,
    required this.gutter,
    this.brandTitle = false,
  });

  final bool brandTitle;

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final ContentWidth width;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.money.line)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xxl, gutter, AppSpacing.xl),
        child: _Constrain(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.md)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (brandTitle)
                      BrandText(title, style: context.display(26))
                    else
                      Text(title, style: context.display(26)),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: context.money.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.lg),
                Row(mainAxisSize: MainAxisSize.min, children: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Caps a column's measure and centres it, so a maximised window leaves margin
/// rather than stretching a ledger row across a monitor (context.md §29).
///
/// Centred, and every page uses the *same* measure. Those two facts depend on
/// each other: centring columns of different widths is what made the whole page
/// slide sideways on every route change. One width, centred, and the layout is
/// nailed down — a page change swaps the content and moves nothing else.
///
/// Where a page needs a narrower measure than the column — a form, whose fields
/// must not stretch to a thousand pixels — it takes it *inside* the column,
/// which is what [SettingsGroup]'s two-column layout does.
class _Constrain extends StatelessWidget {
  const _Constrain({required this.width, required this.child});

  final ContentWidth width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width.maxWidth),
        child: child,
      ),
    );
  }
}

/// A header action: an icon that states what it does on hover and takes a
/// pointer's focus without moving anything around it.
class AppIconAction extends StatelessWidget {
  const AppIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Tints the glyph with the accent — for the one action on a page that is
  /// the reason the user came.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Hoverable(
      builder: (context, hovered) {
        return Tooltip(
          message: tooltip,
          child: Material(
            color: hovered ? context.money.sunken : Colors.transparent,
            borderRadius: AppRadius.fieldAll,
            child: InkWell(
              onTap: onPressed,
              borderRadius: AppRadius.fieldAll,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  icon,
                  size: AppIconSize.md,
                  color: emphasised
                      ? context.colors.primary
                      : hovered
                          ? context.colors.onSurface
                          : context.money.inkMuted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A label over a group of cards. Used where a page has more than one region
/// and the regions need naming without another card around them.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.action, this.trailing});

  final String label;
  final Widget? action;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 0, 0, AppSpacing.md),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: context.money.inkFaint,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Divider(height: 1, color: context.money.line)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            Text(
              trailing!,
              style: TextStyle(fontSize: 11, color: context.money.inkFaint),
            ),
          ],
          if (action != null) ...[const SizedBox(width: AppSpacing.sm), action!],
        ],
      ),
    );
  }
}

/// The row of glyph + word that says which way money ran, for the places where
/// colour alone would be doing the work (context.md §28).
class DirectionTag extends StatelessWidget {
  const DirectionTag({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.background,
    this.border,
  });

  factory DirectionTag.settlement(BuildContext context) => DirectionTag(
        icon: AppIcons.settlement,
        label: 'Settlement',
        color: context.money.inkMuted,
        background: context.money.sunken,
        border: context.money.line,
      );

  final IconData icon;
  final String label;
  final Color color;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppIconSize.xs - 1, color: color),
          const SizedBox(width: AppSpacing.xs + 1),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
