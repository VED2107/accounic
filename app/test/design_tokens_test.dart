import 'dart:math' as math;

import 'package:accounic/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The design tokens, pinned (upgrade §42).
///
/// Two things here are easy to regress by eye and impossible to catch by
/// running the app on one good monitor:
///
///   1. Secondary text drifting down until it is decorative rather than
///      readable. `inkFaint` was #6A7382 on the dark ground, which measures
///      4.03:1 — under the WCAG AA floor for the 12px metadata it carries.
///   2. A financial figure being styled ad hoc instead of taking one of the
///      four sizes, so a balance ends up the same weight as a note.
///
/// Both are asserted as properties rather than as literal values, so the
/// palette can be retuned without the test lying about what it checks.

/// Relative luminance, per WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) {
    final s = v;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Contrast ratio between two opaque colours, 1:1 … 21:1.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('secondary text is readable, not merely restrained', () {
    // The ground each scheme's body text actually sits on.
    const darkGround = Color(0xFF08090C);
    const lightGround = Color(0xFFF6F7F9);

    for (final (name, palette, ground) in [
      ('dark', AccounicColors.dark, darkGround),
      ('light', AccounicColors.light, lightGround),
    ]) {
      test('$name: inkMuted clears AA for body text', () {
        expect(
          _contrast(palette.inkMuted, ground),
          greaterThanOrEqualTo(4.5),
          reason: 'inkMuted carries labels and captions; 4.5:1 is the floor',
        );
      });

      test('$name: inkFaint clears AA for the metadata it carries', () {
        expect(
          _contrast(palette.inkFaint, ground),
          greaterThanOrEqualTo(4.5),
          reason: 'inkFaint carries 12px row metadata, which is body text',
        );
      });

      test('$name: money colours clear AA against the ground', () {
        expect(_contrast(palette.receivable, ground), greaterThanOrEqualTo(4.5));
        expect(_contrast(palette.payable, ground), greaterThanOrEqualTo(4.5));
      });

      test('$name: ink on a filled money button clears AA', () {
        expect(_contrast(palette.receivableInk, palette.receivable), greaterThanOrEqualTo(4.5));
        expect(_contrast(palette.payableInk, palette.payable), greaterThanOrEqualTo(4.5));
      });

      test('$name: inkSubtle is dimmer than inkFaint, and only decorative', () {
        // It exists precisely so that a separator dot can be quiet without
        // dragging real text down with it.
        expect(
          _contrast(palette.inkSubtle, ground),
          lessThan(_contrast(palette.inkFaint, ground)),
        );
      });
    }
  });

  group('a financial figure takes one of four sizes', () {
    late BuildContext ctx;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ));
    }

    testWidgets('they descend in size, and never collide', (tester) async {
      await pump(tester);

      final sizes = [
        ctx.moneyStyle(MoneySize.hero).fontSize!,
        ctx.moneyStyle(MoneySize.large).fontSize!,
        ctx.moneyStyle(MoneySize.row).fontSize!,
        ctx.moneyStyle(MoneySize.small).fontSize!,
      ];

      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason: 'the four steps must be distinguishable at a glance');
      }
    });

    testWidgets('every figure is tabular, so columns line up', (tester) async {
      await pump(tester);

      for (final size in MoneySize.values) {
        final style = ctx.moneyStyle(size);
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: '$size must be tabular or a column of amounts will not align',
        );
        expect(style.fontFamily, 'Poppins');
        // Money is set tighter than body text; positive tracking on a figure
        // makes it read as a serial number.
        expect(style.letterSpacing!, lessThan(0));
      }
    });

    testWidgets('a row figure outweighs the note beside it', (tester) async {
      await pump(tester);

      final row = ctx.moneyStyle(MoneySize.row);
      expect(row.fontWeight!.index, greaterThan(FontWeight.w400.index));
      expect(row.fontSize!, greaterThan(ctx.statNote.fontSize!));
    });

    testWidgets('a stat label sits under the figure it names', (tester) async {
      await pump(tester);

      // Small, wide-tracked, and quieter than the number — the opposite of the
      // figure in every dimension, which is what keeps it from competing.
      expect(ctx.statLabel.fontSize!, lessThan(ctx.moneyStyle(MoneySize.row).fontSize!));
      expect(ctx.statLabel.letterSpacing!, greaterThan(0));
      expect(ctx.statLabel.color, AccounicColors.dark.inkFaint);
    });
  });
}
