import 'package:axon_pos/features/sales/domain/recorded_payment.dart';
import 'package:axon_pos/features/sales/presentation/widgets/record_payment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _message =
    'SKL4X9Q2TB Confirmed. Ksh4,200.00 received from WANJIKU K 0712 678 on 4/11/26 at 11:19 AM.';

Future<void> _open(
  WidgetTester tester, {
  required double total,
  RecordedPaymentRules rules = const RecordedPaymentRules(),
  String method = RecordedPaymentMethod.mpesa,
  String recorderId = 'cashier-1',
  ApproverCheck? approver,
  List<RecordedPaymentDetails?>? sink,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      context = c;
      return const Scaffold(body: SizedBox());
    }),
  ));
  final future = showRecordPaymentSheet(
    context,
    method: method,
    total: total,
    rules: rules,
    recorderId: recorderId,
    recorderName: 'Brian',
    approverForPin: approver ?? (pin) async => null,
  );
  future.then((value) => sink?.add(value));
  await tester.pumpAndSettle();
}

Finder get _submit => find.text('Record and complete sale');

void main() {
  testWidgets('pasting a message fills the code and checks the amount',
      (tester) async {
    await _open(tester, total: 4200);

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.pump();

    expect(find.text('Code: SKL4X9Q2TB'), findsOneWidget);
    expect(find.text('Amount matches: KES 4,200'), findsOneWidget);
    // The code field was filled for the cashier.
    final codeField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(codeField.controller!.text, 'SKL4X9Q2TB');
  });

  testWidgets('a message for a different amount is refused', (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(tester, total: 3000, sink: results);

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('The message says KES 4,200'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('the cashier must confirm they saw the payment', (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(tester, total: 4200, sink: results);

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(
      find.text('Tick the box to confirm you saw this payment in your own M-Pesa.'),
      findsOneWidget,
    );
    expect(results, isEmpty);
  });

  testWidgets('a message is required by default', (tester) async {
    await _open(tester, total: 4200);

    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(
      find.text('Paste the M-Pesa message so the code and amount can be checked.'),
      findsOneWidget,
    );
  });

  testWidgets('a valid payment under the limit records with who saw it',
      (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(tester, total: 4200, sink: results);

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    final details = results.single!;
    expect(details.code, 'SKL4X9Q2TB');
    expect(details.amount, 4200);
    expect(details.recordedByName, 'Brian');
    expect(details.approvedByName, isNull);
    expect(details.message, contains('Confirmed'));
  });

  testWidgets('a payment over the limit asks for a manager PIN',
      (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(
      tester,
      total: 4200,
      rules: const RecordedPaymentRules(approvalLimit: 1000),
      sink: results,
      approver: (pin) async =>
          pin == '2468' ? (id: 'mgr-1', name: 'Wanjiru', isOwner: false) : null,
    );

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.textContaining('A manager or the owner must approve it'),
        findsOneWidget);

    // No PIN yet.
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(find.text('Enter a manager or owner PIN to approve this payment.'),
        findsOneWidget);

    // Wrong PIN.
    await tester.enterText(find.widgetWithText(TextField, 'Manager or owner PIN'), '1111');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(find.text('That PIN does not belong to a manager or the owner.'),
        findsOneWidget);
    expect(results, isEmpty);

    // Right PIN.
    await tester.enterText(find.widgetWithText(TextField, 'Manager or owner PIN'), '2468');
    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(results, hasLength(1));
    expect(results.single!.approvedByName, 'Wanjiru');
    expect(results.single!.approvedById, 'mgr-1');
  });

  testWidgets('a manager cannot approve their own payment', (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(
      tester,
      total: 4200,
      rules: const RecordedPaymentRules(approvalLimit: 1000),
      recorderId: 'mgr-1',
      sink: results,
      approver: (pin) async => (id: 'mgr-1', name: 'Wanjiru', isOwner: false),
    );

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Manager or owner PIN'), '2468');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.text('Another manager or the owner must approve this payment.'),
        findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('the owner may approve a payment they recorded', (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(
      tester,
      total: 4200,
      rules: const RecordedPaymentRules(approvalLimit: 1000),
      recorderId: 'owner-1',
      sink: results,
      approver: (pin) async => (id: 'owner-1', name: 'Wanjiru', isOwner: true),
    );

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Manager or owner PIN'), '2468');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
  });

  testWidgets('a locked-out approver sees the wait message', (tester) async {
    await _open(
      tester,
      total: 4200,
      rules: const RecordedPaymentRules(approvalLimit: 1000),
      approver: (pin) async =>
          throw StateError('Too many wrong PINs. Wait a few minutes before trying again.'),
    );

    await tester.enterText(find.byType(TextField).first, _message);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Manager or owner PIN'), '2468');
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('Too many wrong PINs'), findsOneWidget);
  });

  testWidgets('a bank transfer takes a reference and no message',
      (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(
      tester,
      total: 20000,
      method: RecordedPaymentMethod.bank,
      rules: const RecordedPaymentRules(approvalLimit: 50000),
      sink: results,
    );

    expect(find.text('Paste the M-Pesa message'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'FT26308X1');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single!.method, RecordedPaymentMethod.bank);
    expect(results.single!.code, 'FT26308X1');
  });

  testWidgets('without the message rule an M-Pesa code can be typed',
      (tester) async {
    final results = <RecordedPaymentDetails?>[];
    await _open(
      tester,
      total: 4200,
      rules: const RecordedPaymentRules(requireMessage: false),
      sink: results,
    );

    await tester.enterText(find.widgetWithText(TextField, 'SKL4X9Q2TB'), 'skm2p7r4da');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(_submit);
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single!.code, 'SKM2P7R4DA');
  });
}
