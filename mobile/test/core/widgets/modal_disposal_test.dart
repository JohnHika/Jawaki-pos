import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:axon_pos/core/widgets/modal_disposal.dart';

void main() {
  // Pops a sheet that holds a text field, hands its controller to the
  // helper, then closes the keyboard while the sheet slides away: the same
  // rebuild that crashed "Save till close" on a phone.
  Future<TextEditingController> closeSheetWithKeyboard(
    WidgetTester tester, {
    required bool passRoute,
  }) async {
    final controller = TextEditingController(text: '1280');
    late BuildContext screenContext;
    ModalRoute<dynamic>? sheetRoute;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        screenContext = context;
        return const Scaffold();
      }),
    ));

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    final closed = showModalBottomSheet<void>(
      context: screenContext,
      isScrollControlled: true,
      builder: (sheetContext) {
        sheetRoute ??= ModalRoute.of(sheetContext);
        return Material(child: TextField(controller: controller));
      },
    );
    await tester.pumpAndSettle();

    Navigator.of(screenContext).pop();
    await closed;
    disposeAfterModalCloses([controller], route: passRoute ? sheetRoute : null);

    tester.view.resetViewInsets();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('without the route, waits for the sheet to finish closing',
      (tester) async {
    final controller = await closeSheetWithKeyboard(tester, passRoute: false);

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsNothing);
    expect(() => controller.addListener(() {}), throwsFlutterError,
        reason: 'the controller is disposed once the sheet has gone');
  });

  testWidgets('with the route, disposes when the route is removed',
      (tester) async {
    final controller = await closeSheetWithKeyboard(tester, passRoute: true);

    expect(tester.takeException(), isNull);
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
