import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/sheets/person_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Android person form, at phone metrics with a keyboard up (upgrade §12).
///
/// The reported failure: the keyboard covered the bottom of the screen, Save
/// sat underneath it, and dismissing the keyboard left the form looking stuck.
/// `sheet_actions_test.dart` pins the first half — the actions stay in the
/// viewport at every keyboard height. This pins the rest of it, because a form
/// whose buttons are visible but which cannot be *worked* is no better:
///
///   1. the keyboard can be dismissed by tapping away from the fields,
///   2. dismissing it leaves the form intact and the actions still reachable,
///   3. Next moves to the following field rather than doing nothing,
///   4. every field and action clears the 44pt touch target minimum,
///   5. the currency and opening-balance controls added in this release do not
///      push any of that off the screen.
///
/// None of these is catchable by `flutter analyze` or by a model test, and all
/// of them are what "the form is stuck" actually meant.
void main() {
  // A small Android phone. The failure did not reproduce on a tall screen.
  const screen = Size(360, 640);
  const keyboard = 300.0;

  Future<void> pumpForm(WidgetTester tester, {double inset = 0}) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    // A gesture-navigation device: the bottom inset is not zero even with no
    // keyboard, and the actions have to clear it.
    tester.view.padding = const FakeViewPadding(bottom: 24);
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
  }

  void expectWithinViewport(WidgetTester tester, Finder finder, double inset, String what) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$what is off the top');
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height - inset),
      reason: '$what is underneath the keyboard (bottom ${rect.bottom})',
    );
  }

  testWidgets('the form is usable with the keyboard up', (tester) async {
    await pumpForm(tester, inset: keyboard);

    expectWithinViewport(tester, find.text('Add person'), keyboard, 'Save');
    expectWithinViewport(tester, find.text('Cancel'), keyboard, 'Cancel');
    expect(find.text('Name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping away from a field dismisses the keyboard', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    final field = FocusManager.instance.primaryFocus;
    expect(field, isNotNull, reason: 'the field should have taken focus');

    // The sheet's title is not a field, so a tap on it means "I am done
    // typing" — which is what every other Android form answers to.
    await tester.tap(find.text('Add person or business'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(field)),
      reason: 'the tap should have taken focus off the field, closing the keyboard',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the form survives the keyboard closing', (tester) async {
    await pumpForm(tester, inset: keyboard);

    // The keyboard goes away — the state in which the form "looked stuck".
    tester.view.viewInsets = const FakeViewPadding(bottom: 0);
    await tester.pumpAndSettle();

    expectWithinViewport(tester, find.text('Add person'), 0, 'Save');
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('OPENING BALANCE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Next moves to the following field', (tester) async {
    await pumpForm(tester);

    final name = find.byType(TextField).first;
    await tester.tap(name);
    await tester.pumpAndSettle();
    final first = FocusManager.instance.primaryFocus;

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(first)),
      reason: 'Next did nothing — the fields are not chained',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the actions meet the touch target minimum', (tester) async {
    await pumpForm(tester, inset: keyboard);

    // The whole control, not the label inside it: what has to be 44pt is the
    // thing that answers a thumb.
    final controls = {
      'Cancel': find.byType(OutlinedButton),
      'Save': find.ancestor(
        of: find.text('Add person'),
        matching: find.byType(AnimatedContainer),
      ),
    };

    for (final entry in controls.entries) {
      final box = tester.getRect(entry.value.first);
      expect(
        box.height,
        greaterThanOrEqualTo(44),
        reason: '"${entry.key}" is ${box.height}pt, under the 44pt minimum',
      );
    }
  });

  testWidgets('the currency and opening balance controls are present', (tester) async {
    await pumpForm(tester);

    // The form is grouped into sections (upgrade §1): the heading names the
    // group and the control names itself inside it.
    expect(find.text('CURRENCY'), findsOneWidget);
    expect(find.text('Account currency'), findsOneWidget);
    expect(find.text('OPENING BALANCE'), findsOneWidget);
    expect(find.text('No opening balance'), findsOneWidget);
    expect(find.text('I owe them'), findsOneWidget);
    expect(find.text('They owe me'), findsOneWidget);

    // Choosing a direction reveals the amount without breaking the layout.
    await tester.ensureVisible(find.text('They owe me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('They owe me'));
    await tester.pumpAndSettle();
    expect(find.text('Opening amount'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
