import 'package:axon_pos/features/statements/domain/statement_models.dart';
import 'package:axon_pos/features/statements/presentation/desktop/desktop_statement_replies_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

List<StatementClaim> _claims() => [
      StatementClaim(
        id: 'a',
        kind: 'PAID',
        status: 'PENDING',
        amount: 2500,
        mpesaCode: 'SKL2P0X9QA',
        promisedFor: null,
        payerName: 'Grace W.',
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        debtorName: 'Grace Wanjiru',
        debtorPhone: '0712 345 678',
        outstanding: 4200,
      ),
      StatementClaim(
        id: 'b',
        kind: 'PROMISE',
        status: 'PENDING',
        amount: null,
        mpesaCode: null,
        promisedFor: DateTime(2026, 11, 20),
        payerName: null,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        debtorName: 'Peter Kiprop',
        debtorPhone: null,
        outstanding: 1800,
      ),
      StatementClaim(
        id: 'c',
        kind: 'PROMISE',
        status: 'CONFIRMED',
        amount: null,
        mpesaCode: null,
        promisedFor: DateTime(2026, 11, 12),
        payerName: null,
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        debtorName: 'Amina Hassan',
        debtorPhone: null,
        outstanding: 900,
      ),
    ];

Widget _view({
  List<StatementClaim>? claims,
  bool canDecide = true,
  void Function(StatementClaim, {required bool confirm})? onDecide,
  VoidCallback? onOpenFinance,
  DesktopRepliesNotice? notice,
}) =>
    DesktopStatementRepliesView(
      title: 'Debt Replies',
      claims: claims ?? _claims(),
      canDecide: canDecide,
      notice: notice,
      noticeMessage: 'The server did not answer.',
      onDecide: onDecide ?? (_, {required confirm}) {},
      onOpenFinance: onOpenFinance ?? () {},
      onOpenCustomers: () {},
      onRefresh: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('statement-replies', () => _view(), beforeShot: (tester) async {
    await tester.tap(find.text('Grace Wanjiru'));
    await tester.pumpAndSettle();
  });

  testWidgets('waiting replies show first; All adds the settled ones',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view()));
    await tester.pumpAndSettle();
    expect(find.text('Peter Kiprop'), findsOneWidget);
    expect(find.text('Amina Hassan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('replies-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('Amina Hassan'), findsOneWidget);
  });

  testWidgets('a promise can be noted or rejected from the panel',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    final seen = <String>[];
    await tester.pumpWidget(desktopApp(_view(
      onDecide: (c, {required confirm}) => seen.add('${c.id}:$confirm'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peter Kiprop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reply-noted')));
    await tester.tap(find.byKey(const ValueKey('reply-reject')));
    expect(seen, ['b:true', 'b:false']);
  });

  testWidgets('a paid claim opens Finance, never confirms', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var opened = 0;
    await tester.pumpWidget(desktopApp(_view(onOpenFinance: () => opened++)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grace Wanjiru'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-noted')), findsNothing);
    expect(find.textContaining('not payment confirmation'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reply-open-finance')));
    expect(opened, 1);
  });

  testWidgets('without permission there are no decision buttons',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view(canDecide: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peter Kiprop'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-noted')), findsNothing);
    expect(find.byKey(const ValueKey('reply-reject')), findsNothing);
  });

  testWidgets('Esc closes the open reply', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Peter Kiprop'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-inspector')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reply-inspector')), findsNothing);
  });

  testWidgets('notices replace the table', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(
        _view(claims: const [], notice: DesktopRepliesNotice.localWorkspace)));
    await tester.pumpAndSettle();
    expect(find.text('Replies need a hosted statement link'), findsOneWidget);
    await tester.pumpWidget(
        desktopApp(_view(claims: const [], notice: DesktopRepliesNotice.failed)));
    await tester.pumpAndSettle();
    expect(find.text('The server did not answer.'), findsOneWidget);
    await tester.pumpWidget(desktopApp(_view(claims: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No replies yet'), findsOneWidget);
  });
}
