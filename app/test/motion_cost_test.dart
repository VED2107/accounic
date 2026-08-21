import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/motion.dart';
import 'package:accounic/ui/widgets/app_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a long ledger costs to put on screen.
///
/// The Android build was janky, and none of it was paint: it was controllers.
/// Every row carried an entrance animation, a hover fill and a hover chevron —
/// three `AnimationController`s and three `Ticker`s each — and the people query
/// returns up to 500 rows. Two of the three served hover, which a touch screen
/// cannot produce at all.
///
/// These pin the three fixes. They are cheap assertions about widget counts
/// rather than timings, because a timing test on CI measures the CI machine.
void main() {
  Widget page(List<Widget> children) => MaterialApp(
        theme: AppTheme.dark(),
        home: AppPage(title: 'People', children: children),
      );

  List<Widget> rows(int count) => [
        for (var i = 0; i < count; i++)
          SizedBox(height: 64, child: Text('row $i')),
      ];

  testWidgets('a stagger animates the rows that are watched, not all of them',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page([Stagger(children: rows(300))]));

    // The choreography is capped, so the count is a function of the cap and not
    // of how many people are on the ledger.
    expect(
      find.byType(Animate).evaluate().length,
      Motion.staggerCap + 1,
    );

    await tester.pumpAndSettle();
  });

  testWidgets('a page builds the sections in view, not every section',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Handed over one at a time, so the viewport can decline most of them. The
    // regression: a single child holding a Column of everything is always in
    // view, so nothing is ever skipped.
    await tester.pumpWidget(page(rows(300)));

    expect(find.text('row 0'), findsOneWidget);
    expect(find.text('row 299'), findsNothing);
  });

  testWidgets('handing sections over one at a time keeps the content column',
      (tester) async {
    // The sections used to share one width constraint wrapped around a stretch
    // Column. They are constrained individually now, which has to come out at
    // the same place — a page whose blocks run the full width of a 1400px
    // window would be the obvious way for this change to go wrong.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(rows(3)));
    await tester.pumpAndSettle();

    final row = tester.getRect(find.text('row 0'));
    expect(row.width, lessThan(1000));
    expect(row.center.dx, closeTo(700, 1));
  });

  testWidgets('nothing listens for hover on a touch device', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(Motion.pointerHovers, isFalse);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Hoverable(
          builder: (context, hovered) => HoverFill(
            color: hovered ? const Color(0xFF111111) : const Color(0x00000000),
            child: HoverSlide(
              offset: Offset(hovered ? 0.2 : 0, 0),
              child: const Text('row'),
            ),
          ),
        ),
      ),
    ));

    expect(
      find.descendant(
        of: find.byType(Hoverable),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(AnimatedSlide), findsNothing);
    expect(find.text('row'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a desktop pointer still gets the hover treatment',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(Motion.pointerHovers, isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Hoverable(
          builder: (context, hovered) => HoverFill(
            color: const Color(0x00000000),
            child: HoverSlide(
              offset: Offset.zero,
              child: const Text('row'),
            ),
          ),
        ),
      ),
    ));

    expect(
      find.descendant(
        of: find.byType(Hoverable),
        matching: find.byType(MouseRegion),
      ),
      findsWidgets,
    );
    expect(find.byType(AnimatedContainer), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
