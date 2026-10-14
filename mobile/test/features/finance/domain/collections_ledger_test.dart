import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/finance/domain/bulk_allocation.dart';
import 'package:axon_pos/features/finance/domain/collections_ledger.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';

PeerDebtor _shop(String id, String name) => PeerDebtor(
      id: id,
      tenantId: 't',
      name: name,
      contactName: null,
      phone: null,
      email: null,
      address: null,
      notes: null,
      isActive: true,
      createdAt: null,
      updatedAt: null,
    );

ReceivablePayment _pay(String id, String debt, double amount, DateTime at,
        {String method = 'CASH', String? ref}) =>
    ReceivablePayment(
      id: id,
      receivableId: debt,
      amount: amount,
      method: method,
      reference: ref,
      notes: null,
      paidAt: at,
      createdAt: at,
    );

PeerReceivable _debt(
  String id,
  PeerDebtor shop,
  double original,
  double outstanding, {
  DateTime? due,
  DateTime? created,
  List<ReceivablePayment> payments = const [],
}) =>
    PeerReceivable(
      id: id,
      debtor: shop,
      reference: null,
      description: 'Debt $id',
      originalAmount: original,
      outstandingAmount: outstanding,
      dueDate: due,
      status: outstanding == 0 ? 'PAID' : 'PARTIAL',
      createdAt: created,
      payments: payments,
    );

FinanceSnapshot _snapshot(List<PeerDebtor> shops, List<PeerReceivable> debts) =>
    FinanceSnapshot(
      branchId: 'b',
      supplierPayablesOutstanding: 0,
      retailReceivablesOutstanding: 0,
      peerReceivablesOutstanding: 0,
      payables: const [],
      retailReceivables: const [],
      peerDebtors: shops,
      peerReceivables: debts,
      savedAt: DateTime(2026, 1, 1),
    );

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  final yesterday = today.subtract(const Duration(days: 1));
  final shopX = _shop('x', 'Shop X');
  final shopA = _shop('a', 'Shop A');

  test('statement totals the original debt and what is still owed', () {
    final snap = _snapshot([shopX, shopA], [
      _debt('1', shopX, 10000, 6000, payments: [
        _pay('p1', '1', 3000, yesterday),
        _pay('p2', '1', 1000, today),
      ]),
      _debt('2', shopX, 2000, 0, payments: [_pay('p3', '2', 2000, yesterday)]),
      _debt('3', shopA, 500, 500),
    ]);

    final s = shopStatement(snap, shopX);

    expect(s.originalTotal, 12000);
    expect(s.outstanding, 6000);
    expect(s.paid, 6000);
    expect(s.progress, 0.5);
    expect(s.debts.first.id, '1', reason: 'open debts come before settled ones');
    expect(s.collections.map((e) => e.paymentId), ['p2', 'p1', 'p3'],
        reason: 'newest instalment first');
    expect(shopOutstanding(snap, shopA), 500);
  });

  test('collected totals respect the day boundaries', () {
    final snap = _snapshot([shopX], [
      _debt('1', shopX, 9000, 5000, payments: [
        _pay('p1', '1', 3000, yesterday),
        _pay('p2', '1', 1000, today),
      ]),
    ]);
    final entries = allCollections(snap);

    expect(collectedBetween(entries, startOfDay(today)), 1000);
    expect(collectedBetween(entries, startOfDay(yesterday)), 4000);
    expect(
        collectedBetween(
            entries, startOfDay(yesterday), startOfDay(today)),
        3000);
  });

  test('one instalment spread over two debts reads as a single payment', () {
    final snap = _snapshot([shopX], [
      _debt('1', shopX, 3000, 0, payments: [_pay('p1', '1', 3000, today, ref: 'QK1')]),
      _debt('2', shopX, 5000, 3000, payments: [
        _pay('p2', '2', 2000, today.add(const Duration(seconds: 1)), ref: 'QK1'),
      ]),
    ]);

    final merged = mergeInstalments(allCollections(snap));

    expect(merged, hasLength(1));
    expect(merged.single.amount, 5000);
    expect(merged.single.what, '2 debts');
  });

  test('different references or days stay separate', () {
    final snap = _snapshot([shopX], [
      _debt('1', shopX, 9000, 6000, payments: [
        _pay('p1', '1', 1000, today, ref: 'A'),
        _pay('p2', '1', 2000, today, ref: 'B'),
      ]),
    ]);

    expect(mergeInstalments(allCollections(snap)), hasLength(2));
  });

  test('a shop payment clears the oldest-due debt first, to the cent', () {
    final debts = [
      _debt('late', shopX, 2000, 2000, due: DateTime(2026, 3, 1)),
      _debt('early', shopX, 1000, 1000, due: DateTime(2026, 1, 1)),
      _debt('undated', shopX, 500, 500),
    ];

    final plan = allocatePeerOldestFirst(debts, 1500.50);

    expect(plan.allocations.map((a) => a.receivableId), ['early', 'late']);
    expect(plan.allocations.map((a) => a.amount), [1000, 500.5]);
    expect(plan.unallocated, 0);
  });
}
