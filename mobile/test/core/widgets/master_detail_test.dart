import 'package:axon_pos/core/widgets/master_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  Widget? detail,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MasterDetail(
          emptyTitle: 'Pick one',
          detail: detail,
          masterBuilder: (context, twoPane) => Text(
            twoPane ? 'list (two panes)' : 'list (one pane)',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a phone shows only the list', (tester) async {
    await _pump(tester, const Size(390, 844));
    expect(find.text('list (one pane)'), findsOneWidget);
    expect(find.text('Pick one'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet or an unfolded fold phone shows list and detail',
      (tester) async {
    await _pump(tester, const Size(800, 1280));
    expect(find.text('list (two panes)'), findsOneWidget);
    expect(find.text('Pick one'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picked item replaces the prompt', (tester) async {
    await _pump(tester, const Size(720, 1000), detail: const Text('The item'));
    expect(find.text('The item'), findsOneWidget);
    expect(find.text('Pick one'), findsNothing);
  });

  testWidgets('a landscape terminal does not overflow', (tester) async {
    await _pump(tester, const Size(1024, 768));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wantsTwoPanes follows the page width', (tester) async {
    late BuildContext captured;
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    expect(MasterDetail.wantsTwoPanes(captured, 700), isTrue);
    expect(MasterDetail.wantsTwoPanes(captured, 500), isFalse);
  });
}
