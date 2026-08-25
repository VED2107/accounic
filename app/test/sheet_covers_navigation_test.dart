import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/sheets/sheet_scaffold.dart';

/// A form must own the screen it is on (upgrade §41, §3).
///
/// The application shell draws four destinations and a docked add button along
/// the bottom edge of every phone screen. A sheet pushed on the *shell's* nested
/// navigator opens inside that Scaffold, which leaves the bar and the `+` drawn
/// over the form — a second, meaningless action area on the exact edge of the
/// screen the thumb reaches for Save.
///
/// [showAppSheet] roots its route on the top-level navigator, so the shell's
/// navigation is covered for as long as the form is open and back the moment it
/// closes, with no state for anyone to keep in step. That is the behaviour these
/// tests pin: it is structural, invisible in a screenshot, and exactly the kind
/// of thing a later refactor removes by accident.
void main() {
  const compact = Size(390, 844);

  /// A shell in the shape go_router builds: a Scaffold with a bottom bar whose
  /// body is its own nested Navigator.
  Widget shell({required VoidCallback onNavTap, required WidgetBuilder page}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(builder: page),
        ),
        bottomNavigationBar: SizedBox(
          height: 62,
          child: Center(
            child: TextButton(onPressed: onNavTap, child: const Text('People')),
          ),
        ),
      ),
    );
  }

  testWidgets('an open sheet covers the shell navigation', (tester) async {
    tester.view.physicalSize = compact;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var navTaps = 0;

    await tester.pumpWidget(
      shell(
        onNavTap: () => navTaps++,
        page: (context) => Center(
          child: TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              (context) => SheetScaffold(
                title: 'Add person',
                primaryLabel: 'Add person',
                onPrimary: () {},
                children: const [SizedBox(height: 200)],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Add person'), findsWidgets, reason: 'the sheet did not open');

    // The bar is still mounted — it is underneath, not unbuilt — but it is no
    // longer reachable, because the sheet's route sits above the whole shell.
    // Tapping where a destination is hits the modal barrier instead.
    await tester.tap(find.text('People'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      navTaps,
      0,
      reason: 'the bottom bar was still live under an open form — the sheet was '
          'pushed on the shell navigator rather than the root one',
    );
  });

  testWidgets('closing the sheet gives the navigation back', (tester) async {
    tester.view.physicalSize = compact;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var navTaps = 0;

    await tester.pumpWidget(
      shell(
        onNavTap: () => navTaps++,
        page: (context) => Center(
          child: TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              (context) => SheetScaffold(
                title: 'Add person',
                primaryLabel: 'Add person',
                onPrimary: () {},
                children: const [SizedBox(height: 200)],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Cancel is the sheet's own dismissal, and the one a user reaches for.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsNothing, reason: 'the sheet did not close');

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    expect(navTaps, 1, reason: 'navigation did not come back after the form closed');
  });
}
