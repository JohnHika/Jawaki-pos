import 'package:axon_pos/features/statements/presentation/desktop/desktop_match_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

final _rows = <DesktopMatchRow>[
  DesktopMatchRow(
    saleId: 's1',
    code: 'SKL4Q8X2AB',
    amount: 1250,
    isBank: false,
    state: DesktopMatchState.matched,
    time: DateTime(2026, 11, 10, 9, 14),
    recordedBy: 'Asha',
  ),
  DesktopMatchRow(
    saleId: 's2',
    code: 'SKL4Q9ZZ12',
    amount: 830,
    isBank: false,
    state: DesktopMatchState.differs,
    time: DateTime(2026, 11, 10, 10, 2),
    recordedBy: 'Njeri',
    statementAmounts: const [380],
  ),
  DesktopMatchRow(
    saleId: 's3',
    code: 'BNK-77120',
    amount: 15400,
    isBank: true,
    state: DesktopMatchState.notFound,
    time: DateTime(2026, 11, 10, 11, 40),
    recordedBy: 'Asha',
  ),
  DesktopMatchRow(
    saleId: 's4',
    code: 'SKL4R1MM90',
    amount: 400,
    isBank: false,
    state: DesktopMatchState.checked,
    time: DateTime(2026, 11, 10, 12, 5),
    checkNote: 'Saw the message on the cashier phone',
    checkedBy: 'Owner',
  ),
];

DesktopMatchView _view({
  List<DesktopMatchRow>? rows,
  String statement = 'SKL4Q8X2AB Confirmed. Ksh1,250.00 received',
  String? selected,
  void Function(DesktopMatchRow row, String note)? onSave,
}) =>
    DesktopMatchView(
      rows: rows ?? _rows,
      statement: TextEditingController(text: statement),
      onStatementChanged: () {},
      onPaste: () {},
      onSaveCheck: onSave ?? (_, __) {},
      initialSelectedId: selected,
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('match-payments', () => _view());
  shotMatrix('match-payments-selected', () => _view(selected: 's2'));
  shotMatrix('match-payments-empty', () => _view(rows: const []));

  testWidgets('a payment the statement does not confirm is marked checked '
      'with a note', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    DesktopMatchRow? saved;
    String? savedNote;
    await tester.pumpWidget(desktopApp(
      _view(onSave: (row, note) {
        saved = row;
        savedNote = note;
      }),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('BNK-77120'));
    await tester.pumpAndSettle();
    expect(find.text('Mark checked'), findsOneWidget);

    // A note shorter than three letters is refused.
    await tester.enterText(find.byType(TextField).last, 'ok');
    await tester.tap(find.text('Mark checked'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Write a few words'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Saw the bank entry');
    await tester.tap(find.text('Mark checked'));
    await tester.pump();
    expect(saved?.saleId, 's3');
    expect(savedNote, 'Saw the bank entry');
  });

  testWidgets('the To check filter hides matched and checked payments',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view()));
    await tester.pumpAndSettle();
    expect(find.text('SKL4Q8X2AB'), findsOneWidget);

    await tester.tap(find.text('To check').last);
    await tester.pumpAndSettle();
    expect(find.text('SKL4Q8X2AB'), findsNothing);
    expect(find.text('BNK-77120'), findsOneWidget);
    expect(find.text('SKL4Q9ZZ12'), findsOneWidget);
  });
}
