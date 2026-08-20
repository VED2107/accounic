import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/sheets/sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cancel closes the sheet — whatever the route's result type is.
///
/// The regression this pins: [SheetScaffold] is shared chrome, and it used to
/// cancel with `Navigator.pop(false)`. That is fine on a `Route<bool>` and a
/// **runtime type error** on any other — and the person sheet's route is a
/// `Route<Person>`. The throw was swallowed by the gesture handler, so the
/// symptom was not a crash but a Cancel button that did nothing at all, on
/// exactly the sheets whose result was not a bool.
///
/// The fix is that Cancel pops *nothing*. Every caller already reads a null
/// result as "the user backed out", so null is both type-safe on every route
/// and the correct answer on every one of them.
void main() {
  /// A stand-in for any non-bool result type a sheet might carry.
  const person = 'Priya Nair';

  Widget host<T>({required void Function(T?) onClosed}) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await showAppSheet<T>(
                  context,
                  (context) => SheetScaffold(
                    title: 'Add person',
                    primaryLabel: 'Save',
                    onPrimary: () {},
                    children: const [SizedBox(height: 40)],
                  ),
                );
                onClosed(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('sheet cancel', () {
    testWidgets('closes a sheet whose route carries a non-bool result',
        (tester) async {
      // A phone width, so the sheet is presented as a bottom sheet.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      String? result = person;
      var closed = false;

      await tester.pumpWidget(host<String>(onClosed: (value) {
        result = value;
        closed = true;
      }));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add person'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add person'), findsNothing, reason: 'the sheet must close');
      expect(closed, isTrue);
      expect(result, isNull, reason: 'cancelling reports no result');
    });

    testWidgets('closes the desktop panel presentation too', (tester) async {
      // A desktop width, where showAppSheet presents a centred panel instead.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var closed = false;

      await tester.pumpWidget(host<String>(onClosed: (_) => closed = true));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add person'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Add person'), findsNothing);
      expect(closed, isTrue);
    });

    testWidgets('a bool-typed sheet still reports null on cancel, not false',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      bool? result = true;

      await tester.pumpWidget(host<bool>(onClosed: (value) => result = value));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The callers all write `result ?? false`, so null and false mean the
      // same thing to them — but null is the one that is type-safe everywhere.
      expect(result, isNull);
    });
  });
}
