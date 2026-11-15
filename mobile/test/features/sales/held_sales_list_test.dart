import 'package:axon_pos/features/sales/presentation/desktop/held_sales_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

final _now = DateTime(2026, 11, 15, 12, 0);

List<HeldSaleRowData> _rows() => [
      HeldSaleRowData(
        id: 'a',
        label: 'Wanjiru Mwangi',
        itemCount: 4,
        total: 1180,
        parkedAt: _now.subtract(const Duration(minutes: 12)),
      ),
      HeldSaleRowData(
        id: 'b',
        label: 'Held sale',
        itemCount: 1,
        total: 95.5,
        parkedAt: _now.subtract(const Duration(hours: 3)),
      ),
    ];

Widget _list({
  List<HeldSaleRowData>? rows,
  bool restoring = false,
  String? warning,
  List<String>? log,
}) =>
    Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 580,
        child: HeldSalesList(
          rows: rows ?? _rows(),
          restoring: restoring,
          warning: warning,
          now: _now,
          onResume: (id) => log?.add('resume $id'),
          onDiscard: (id) => log?.add('discard $id'),
        ),
      ),
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('held-sales', () => _list());
  shotMatrix('held-sales-empty', () => _list(rows: const []));
  shotMatrix(
    'held-sales-warning',
    () => _list(warning: 'Some held sales could not be restored.'),
  );

  test('age reads naturally', () {
    expect(heldSaleAge(_now, _now), 'just now');
    expect(
      heldSaleAge(_now.subtract(const Duration(minutes: 12)), _now),
      '12 min ago',
    );
    expect(
      heldSaleAge(_now.subtract(const Duration(days: 2)), _now),
      '2 days ago',
    );
  });

  testWidgets('arrows choose, Enter resumes, Delete discards', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(desktopApp(_list(log: log)));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(log, ['resume a']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(log.last, 'resume b');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(log.last, 'discard b');
  });

  testWidgets('a restore warning blocks resuming and discarding',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final log = <String>[];
    await tester.pumpWidget(
      desktopApp(_list(warning: 'Could not restore all.', log: log)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(log, isEmpty);
    expect(find.byKey(const ValueKey('held-warning')), findsOneWidget);
  });

  testWidgets('buttons resume and discard the row they sit on',
      (tester) async {
    useWindow(tester, desktopSizes['1093']!);
    final log = <String>[];
    await tester.pumpWidget(desktopApp(_list(log: log)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resume-b')));
    await tester.tap(find.byKey(const ValueKey('discard-a')));
    expect(log, ['resume b', 'discard a']);
  });
}
