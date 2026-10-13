import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/payments/domain/manual_payment.dart';
import 'package:axon_pos/features/payments/presentation/screens/manual_payments_screen.dart';

class _FakeApi implements ManualPaymentsApi {
  _FakeApi(this.requests);

  List<ManualPaymentRequest> requests;
  final List<String> approved = [];
  final List<(String, String)> rejected = [];
  Map<String, Object?>? created;
  Object? createError;
  String? lastStatusFilter = 'unset';

  @override
  Future<List<ManualPaymentRequest>> list({String? status}) async {
    lastStatusFilter = status;
    return requests.where((r) => status == null || r.status == status).toList();
  }

  @override
  Future<void> create({
    required String paymentMethod,
    required double amount,
    required String reason,
    String? notes,
  }) async {
    final failure = createError;
    if (failure != null) throw failure;
    created = {'method': paymentMethod, 'amount': amount, 'reason': reason};
  }

  @override
  Future<void> approve(String id) async => approved.add(id);

  @override
  Future<void> reject(String id, String reason) async =>
      rejected.add((id, reason));
}

ManualPaymentRequest _request({
  String id = 'req-1',
  String status = 'PENDING',
  String requestedById = 'cashier-1',
}) =>
    ManualPaymentRequest(
      id: id,
      requestNumber: 'MPR-20261013-ABC123',
      branchId: 'branch-1',
      paymentMethod: 'bank_transfer',
      amount: 1500,
      reason: 'Paid by bank transfer',
      status: status,
      requestedById: requestedById,
      requestedBy: 'Ada Cashier',
      createdAt: DateTime.utc(2026, 10, 13, 9),
    );

Widget _host(_FakeApi api, {required String userId, required List<String> perms}) =>
    ProviderScope(
      overrides: [
        manualPaymentsApiProvider.overrideWithValue(api),
        currentUserProvider
            .overrideWithValue({'id': userId, 'permissions': perms}),
      ],
      child: const MaterialApp(home: ManualPaymentsScreen()),
    );

void main() {
  testWidgets('a manager can approve someone else\'s pending request',
      (tester) async {
    final api = _FakeApi([_request()]);
    await tester.pumpWidget(_host(api,
        userId: 'manager-1',
        perms: ['payments.view_status', 'payments.manual_approve']));
    await tester.pumpAndSettle();

    expect(find.text('KES 1,500'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('approve-req-1')));
    await tester.pumpAndSettle();

    expect(api.approved, ['req-1']);
    expect(find.text('Payment approved'), findsOneWidget);
  });

  testWidgets('rejecting requires a reason and sends it', (tester) async {
    final api = _FakeApi([_request()]);
    await tester.pumpWidget(_host(api,
        userId: 'manager-1',
        perms: ['payments.view_status', 'payments.manual_approve']));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reject-req-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Give a short reason'), findsOneWidget);
    expect(api.rejected, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('reject-reason')), 'No slip provided');
    await tester.tap(find.byKey(const ValueKey('reject-confirm')));
    await tester.pumpAndSettle();

    expect(api.rejected, [('req-1', 'No slip provided')]);
  });

  testWidgets('nobody sees approve/reject on their own request',
      (tester) async {
    final api = _FakeApi([_request(requestedById: 'manager-1')]);
    await tester.pumpWidget(_host(api,
        userId: 'manager-1',
        perms: ['payments.view_status', 'payments.manual_approve']));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approve-req-1')), findsNothing);
    expect(find.byKey(const ValueKey('reject-req-1')), findsNothing);
  });

  testWidgets('a cashier can request approval but cannot decide',
      (tester) async {
    final api = _FakeApi([_request()]);
    await tester.pumpWidget(_host(api,
        userId: 'cashier-2', perms: ['payments.view_status', 'sales.create']));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('approve-req-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('manual-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('manual-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Amount must be greater than zero'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('manual-amount')), '750');
    await tester.enterText(
        find.byKey(const ValueKey('manual-reason')), 'Cheque 0042');
    await tester.tap(find.byKey(const ValueKey('manual-submit')));
    await tester.pumpAndSettle();

    expect(api.created,
        {'method': 'bank_transfer', 'amount': 750.0, 'reason': 'Cheque 0042'});
    expect(find.text('Sent to a manager for approval'), findsOneWidget);
  });

  testWidgets('a failed request keeps the sheet open with the reason',
      (tester) async {
    final api = _FakeApi(const [])..createError = StateError('Choose a branch');
    await tester.pumpWidget(_host(api,
        userId: 'cashier-2', perms: ['payments.view_status', 'sales.create']));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('manual-amount')), '100');
    await tester.enterText(
        find.byKey(const ValueKey('manual-reason')), 'Transfer');
    await tester.tap(find.byKey(const ValueKey('manual-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a branch'), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-submit')), findsOneWidget);
  });

  testWidgets('the All filter loads every status', (tester) async {
    final api = _FakeApi([_request(), _request(id: 'req-2', status: 'REJECTED')]);
    await tester.pumpWidget(_host(api,
        userId: 'manager-1',
        perms: ['payments.view_status', 'payments.manual_approve']));
    await tester.pumpAndSettle();
    expect(api.lastStatusFilter, 'PENDING');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(api.lastStatusFilter, isNull);
    expect(find.text('Rejected'), findsOneWidget);
  });
}
