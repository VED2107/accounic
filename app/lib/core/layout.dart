library;

import 'package:flutter/widgets.dart';

/// The responsive system (context.md §29).
///
/// One scale, four bands, consulted through [BuildContext] so no widget ever
/// hardcodes a pixel width or reaches for `Platform.isX`. A Windows window
/// narrowed to phone width gets the phone layout; an Android tablet in
/// landscape gets the desktop one. Width is the only input.
enum Breakpoint {
  /// Phones, and any window narrowed to their width.
  compact,

  /// Small tablets, split-screen windows.
  medium,

  /// The ordinary desktop window.
  expanded,

  /// A maximised window on a large monitor.
  large;

  static Breakpoint of(double width) {
    if (width < 600) return Breakpoint.compact;
    if (width < 900) return Breakpoint.medium;
    if (width < 1440) return Breakpoint.expanded;
    return Breakpoint.large;
  }

  bool get isCompact => this == Breakpoint.compact;

  /// True where the shell shows a rail rather than a bottom bar, and where a
  /// screen may assume a pointer.
  bool get isWide => index >= Breakpoint.expanded.index;

  /// Room for two columns of cards side by side.
  bool get isMedium => index >= Breakpoint.medium.index;
}

/// The spacing scale. Four-pixel base; nothing between the steps.
///
/// These are the only vertical and horizontal gaps in the product. A gap that
/// is not one of these reads as a mistake next to the ones that are.
abstract final class AppSpacing {
  /// 4 — inside a chip, between an icon and its own label.
  static const double xs = 4;

  /// 8 — between tightly bound elements.
  static const double sm = 8;

  /// 12 — inside a dense row.
  static const double md = 12;

  /// 16 — the default: card padding on a phone, the gap between cards.
  static const double lg = 16;

  /// 20 — card padding on a desktop.
  static const double xl = 20;

  /// 24 — between a section and the next one.
  static const double xxl = 24;

  /// 32 — between major regions of a page.
  static const double xxxl = 32;
}

/// Corner radii. Small for controls, medium for cards, large for the surfaces
/// that present themselves as sheets.
abstract final class AppRadius {
  static const double chip = 100;
  static const double field = 10;
  static const double card = 16;
  static const double panel = 20;

  static const BorderRadius fieldAll = BorderRadius.all(Radius.circular(field));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelAll = BorderRadius.all(Radius.circular(panel));
}

/// How wide a column of content is allowed to grow.
///
/// A ledger row stretched across a 3440px monitor is unreadable — the eye
/// cannot carry a name on the left to a figure on the right. The page chrome
/// caps the column at one of these and centres it.
///
/// **Every screen uses [standard].** The other two exist for the odd panel that
/// genuinely needs its own measure, but a page must not take one lightly: a
/// centred column whose width changes per route makes the entire layout jump
/// sideways whenever the user changes page, which is far more noticeable than
/// any one page being fifty pixels wider than it strictly needed to be.
enum ContentWidth {
  /// A single form, on its own, with nothing beside it.
  narrow(720),

  /// The product's measure. Wide enough for a ledger row with a name, a date
  /// and a figure; short enough that the eye carries across it.
  standard(1040),

  /// Reserved for a future screen that genuinely needs three columns.
  wide(1240);

  const ContentWidth(this.maxWidth);

  final double maxWidth;
}

extension LayoutContext on BuildContext {
  Breakpoint get breakpoint => Breakpoint.of(MediaQuery.sizeOf(this).width);

  bool get isCompact => breakpoint.isCompact;

  bool get isWide => breakpoint.isWide;

  /// The page gutter for this width. Grows with the window so content never
  /// touches the chrome, and never grows past the point where it reads as an
  /// indent rather than a margin.
  double get gutter => switch (breakpoint) {
        Breakpoint.compact => AppSpacing.lg,
        Breakpoint.medium => AppSpacing.xl,
        _ => AppSpacing.xxl,
      };

  /// Padding inside a card, which is tighter on a phone than on a desktop.
  EdgeInsets get cardPadding => EdgeInsets.all(isCompact ? AppSpacing.lg : AppSpacing.xl);
}
