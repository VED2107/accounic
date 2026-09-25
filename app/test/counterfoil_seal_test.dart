import 'package:accounic/core/theme.dart';
import 'package:accounic/ui/sheets/sheet_scaffold.dart';
import 'package:accounic/ui/widgets/instrument.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counterfoil & Seal (v1.16): the behaviours the new world adds.
///
/// * A destructive confirmation is HELD, not tapped. A tap must not delete
///   anything; a full hold must; the keyboard confirms at once, because a hold
///   is a pointer affordance and never a barrier to anyone else.
/// * Every stamp the product strikes paints without error at every size it is
///   used at, in both schemes — a painter that throws takes a whole row with it.
void main() {
  Widget host({required ThemeData theme, required void Function(bool) onResult}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                onResult(await confirm(
                  context,
                  title: 'Delete this account?',
                  body: 'This cannot be undone.',
                  confirmLabel: 'Delete',
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('hold to confirm', () {
    testWidgets('a tap does not confirm a destructive action', (tester) async {
      bool? result;
      await tester.pumpWidget(host(theme: AppTheme.dark(), onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hold to delete'));
      await tester.pumpAndSettle();

      expect(result, isNull, reason: 'the dialog must still be open');
      expect(find.text('Keep holding'), findsOneWidget);
    });

    testWidgets('a full hold confirms', (tester) async {
      bool? result;
      await tester.pumpWidget(host(theme: AppTheme.dark(), onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(find.text('Hold to delete')));
      // The first frame starts the fill's ticker; the hold is timed from it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1300));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('the keyboard confirms at once', (tester) async {
      bool? result;
      await tester.pumpWidget(host(theme: AppTheme.light(), onResult: (r) => result = r));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tab to the hold control (Cancel first, then it) and press Enter.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });

  testWidgets('every stamp paints at every size, in both schemes', (tester) async {
    for (final theme in [AppTheme.dark(), AppTheme.light()]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Wrap(children: [
            CancellationStamp(color: Colors.green, size: 24, word: 'VOID', shape: StampShape.box),
            CancellationStamp(color: Colors.green, size: 46),
            CancellationStamp(color: Colors.red, size: 48, word: 'RECEIVED'),
            CancellationStamp(color: Colors.red, size: 74, detail: 'OPENING'),
            CancellationStamp(color: Colors.green, size: 132, detail: '25 SEP', land: true),
            SizedBox(width: 300, height: 120, child: GuillocheField()),
            SizedBox(width: 300, child: Perforation()),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  test('a serial is the id, shortened the way a cheque number is', () {
    expect(serialOf('cd62c1aa-1234-5678'), 'CD62·C1');
    expect(serialOf('ab'), 'AB');
  });
}
