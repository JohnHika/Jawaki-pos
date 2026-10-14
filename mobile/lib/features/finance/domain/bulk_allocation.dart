import 'finance_models.dart';

/// One slice of a collected amount applied to a single receivable.
class ReceivableAllocation {
  const ReceivableAllocation({required this.receivableId, required this.amount});

  final String receivableId;
  final double amount;
}

class BulkAllocationPlan {
  const BulkAllocationPlan({required this.allocations, required this.unallocated});

  final List<ReceivableAllocation> allocations;

  /// Money left over once every open receivable is fully covered.
  final double unallocated;

  double get total => allocations.fold(0, (sum, a) => sum + a.amount);
}

/// Splits [amount] across [receivables], settling the oldest-due balances first.
///
/// Works in whole cents so repeated partial payments never drift by a fraction.
/// Receivables with nothing outstanding are skipped; undated ones go last.
BulkAllocationPlan allocateOldestFirst(
  List<RetailReceivable> receivables,
  double amount,
) =>
    _allocate(
      receivables
          .map((r) => _Owed(r.id, r.outstandingAmount, r.dueDate, r.createdAt))
          .toList(),
      amount,
    );

/// Same oldest-due-first split, for what another shop owes us.
BulkAllocationPlan allocatePeerOldestFirst(
  List<PeerReceivable> receivables,
  double amount,
) =>
    _allocate(
      receivables
          .map((r) => _Owed(r.id, r.outstandingAmount, r.dueDate, r.createdAt))
          .toList(),
      amount,
    );

class _Owed {
  const _Owed(this.id, this.outstanding, this.dueDate, this.createdAt);
  final String id;
  final double outstanding;
  final DateTime? dueDate;
  final DateTime? createdAt;
}

BulkAllocationPlan _allocate(List<_Owed> receivables, double amount) {
  var remaining = _toCents(amount);
  final open = receivables.where((r) => _toCents(r.outstanding) > 0).toList()
    ..sort(_oldestFirst);

  final allocations = <ReceivableAllocation>[];
  for (final receivable in open) {
    if (remaining <= 0) break;
    final owed = _toCents(receivable.outstanding);
    final applied = remaining < owed ? remaining : owed;
    allocations.add(ReceivableAllocation(
      receivableId: receivable.id,
      amount: applied / 100,
    ));
    remaining -= applied;
  }
  return BulkAllocationPlan(
    allocations: allocations,
    unallocated: (remaining < 0 ? 0 : remaining) / 100,
  );
}

int _toCents(double value) => (value * 100).round();

int _oldestFirst(_Owed a, _Owed b) {
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null) {
    final byDue = aDue.compareTo(bDue);
    if (byDue != 0) return byDue;
  } else if (aDue != null) {
    return -1;
  } else if (bDue != null) {
    return 1;
  }
  final aCreated = a.createdAt;
  final bCreated = b.createdAt;
  if (aCreated != null && bCreated != null) return aCreated.compareTo(bCreated);
  return 0;
}
