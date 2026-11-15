import 'package:axon_pos/core/widgets/alive_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(void Function(BuildContext) onTap) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onTap(context),
            child: const Text('go'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a finished action is acknowledged and undo calls back', (tester) async {
    var undone = false;
    await tester.pumpWidget(_host((context) => Alive.done(
          context,
          'Saved',
          onUndo: () => undone = true,
        )));

    await tester.tap(find.text('go'));
    // The action fades in after the bar slides up.
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Saved'), findsOneWidget);
    final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    expect(action.label, 'Undo');
    action.onPressed();
    expect(undone, isTrue);
  });

  testWidgets('run reports success once the action has finished', (tester) async {
    bool? result;
    await tester.pumpWidget(_host((context) async {
      result = await Alive.run(context, () async {}, done: 'Price saved');
    }));

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(result, isTrue);
    expect(find.text('Price saved'), findsOneWidget);
  });

  testWidgets('run explains a failure instead of claiming success', (tester) async {
    bool? result;
    await tester.pumpWidget(_host((context) async {
      result = await Alive.run(
        context,
        () async => throw StateError('no'),
        done: 'Price saved',
        failed: 'Could not save the price.',
      );
    }));

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(result, isFalse);
    expect(find.text('Price saved'), findsNothing);
    expect(find.text('Could not save the price.'), findsOneWidget);
  });

  testWidgets('AliveIcon shows the check while done', (tester) async {
    Widget icon(bool done) => MaterialApp(
          home: AliveIcon(done: done, idle: const Icon(Icons.copy_rounded)),
        );
    await tester.pumpWidget(icon(false));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

    await tester.pumpWidget(icon(true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });
}
