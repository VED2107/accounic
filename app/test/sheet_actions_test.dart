import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/sheets/person_sheet.dart';
import 'package:accounic/ui/sheets/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sheet's actions are reachable at every keyboard height.
///
/// The regression: Cancel and the primary action were the last children *inside*
/// the sheet's scroll view, and the panel was sized against the full screen
/// height rather than against what was left after the keyboard. So on a phone
/// with the keyboard up — which is the normal state of the person sheet, whose
/// name field autofocuses — the actions were laid out at y≈717 on a 780pt screen
/// with only 460pt visible. They were underneath the keyboard, and the only way
/// to reach them was to scroll past every field.
///
/// They are pinned to the foot of the panel now. These assert the property that
/// matters — the actions are inside the visible viewport — rather than any
/// particular geometry, so the numbers can move without the test lying.
void main() {
  const screen = Size(360, 780);

  /// Every keyboard height worth caring about: none, a normal one, and a tall
  /// one with a suggestion strip on a short device.
  const insets = [0.0, 260.0, 320.0, 420.0];

  void expectReachable(WidgetTester tester, double inset, String primary) {
    final visibleBottom = screen.height - inset;

    for (final label in [primary, 'Cancel']) {
      final rect = tester.getRect(find.text(label));
      expect(
        rect.top,
        greaterThanOrEqualTo(0),
        reason: '"$label" is off the top of the screen with a $inset keyboard',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(visibleBottom),
        reason: '"$label" is underneath a $inset keyboard '
            '(bottom ${rect.bottom}, visible to $visibleBottom)',
      );
    }
  }

  group('sheet actions stay reachable', () {
    for (final inset in insets) {
      testWidgets('shared chrome, keyboard $inset', (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    (context) => SheetScaffold(
                      title: 'A sheet with more fields than fit',
                      primaryLabel: 'Save',
                      onPrimary: () {},
                      // Deliberately far taller than any phone: the actions must
                      // not depend on the content being short enough.
                      children: [
                        for (var i = 0; i < 12; i++)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: SizedBox(height: 64, child: Text('field')),
                          ),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expectReachable(tester, inset, 'Save');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the person sheet, keyboard $inset', (tester) async {
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: ElevatedButton(
                    onPressed: () => showPersonSheet(context, ref),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expectReachable(tester, inset, 'Add person');

        // The first field is still the one in view: pinning the foot must not
        // have pushed the top of the form off the screen.
        expect(find.text('Name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
