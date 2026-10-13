import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/finance/domain/bulk_allocation.dart';
import 'package:axon_pos/features/finance/domain/finance_models.dart';

RetailReceivable _credit(
  String id,
  double outstanding, {
  DateTime? due,
  DateTime? created,
}) =>
    RetailReceivable(
      id: id,
      saleId: 'sale-$id',
      receiptNumber: 'R-$id',
      customerId: 'c-1',
      customerName: 'Wanjiru',
      originalAmount: outstanding,
      outstandingAmount: outstanding,
      dueDate: due,
      status: 'OPEN',
      createdAt: created,
      payments: const <ReceivablePayment>[],
    );

void main() {
  group('allocateOldestFirst', () {
    test('settles the earliest due credit first and carries the rest forward', () {
      final plan = allocateOldestFirst([
        _credit('late', 100, due: DateTime.utc(2026, 10, 20)),
        _credit('early', 80, due: DateTime.utc(2026, 10, 1)),
      ], 120);

      expect(plan.allocations.map((a) => a.receivableId), ['early', 'late']);
      expect(plan.allocations.map((a) => a.amount), [80.0, 40.0]);
      expect(plan.unallocated, 0);
      expect(plan.total, 120);
    });

    test('puts undated credits after dated ones, oldest created first', () {
      final plan = allocateOldestFirst([
        _credit('undated-new', 10, created: DateTime.utc(2026, 10, 5)),
        _credit('undated-old', 10, created: DateTime.utc(2026, 10, 1)),
        _credit('dated', 10, due: DateTime.utc(2026, 12, 1)),
      ], 30);

      expect(plan.allocations.map((a) => a.receivableId),
          ['dated', 'undated-old', 'undated-new']);
    });

    test('stops once the money runs out and leaves later credits untouched', () {
      final plan = allocateOldestFirst([
        _credit('a', 50, due: DateTime.utc(2026, 10, 1)),
        _credit('b', 50, due: DateTime.utc(2026, 10, 2)),
      ], 30);

      expect(plan.allocations.length, 1);
      expect(plan.allocations.single.amount, 30);
    });

    test('reports money left over when the customer pays more than they owe', () {
      final plan = allocateOldestFirst([_credit('a', 50)], 80);

      expect(plan.allocations.single.amount, 50);
      expect(plan.unallocated, 30);
    });

    test('does not drift on fractional amounts', () {
      final plan = allocateOldestFirst([
        _credit('a', 0.1, due: DateTime.utc(2026, 10, 1)),
        _credit('b', 0.2, due: DateTime.utc(2026, 10, 2)),
      ], 0.3);

      expect(plan.allocations.map((a) => a.amount), [0.1, 0.2]);
      expect(plan.unallocated, 0);
    });

    test('skips settled credits and handles an empty list', () {
      expect(allocateOldestFirst([_credit('paid', 0)], 10).allocations, isEmpty);
      expect(allocateOldestFirst(const [], 10).unallocated, 10);
    });
  });
}
