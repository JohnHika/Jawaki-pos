import 'setup_pricing.dart';

/// Where a shop stands with its payments to Arche Axon.
enum LicenceStatus {
  /// No payment yet and still inside the free trial.
  trial,

  /// Paid up; nothing is overdue.
  active,

  /// A payment is overdue but inside the grace days. Everything still works.
  grace,

  /// Grace has ended. New sales pause. Records stay open.
  salesPaused,
}

class LicenceStanding {
  const LicenceStanding({
    required this.status,
    required this.dueAt,
    required this.daysLeft,
  });

  final LicenceStatus status;

  /// When the next payment, or the end of the trial, falls due.
  final DateTime dueAt;

  /// Whole days until the next change: until due (trial, active), until sales
  /// pause (grace), or 0 once paused.
  final int daysLeft;

  /// New sales are allowed unless sales are paused.
  bool get canSell => status != LicenceStatus.salesPaused;

  /// A shop can always look at and export its own records, whatever its
  /// standing. This is a promise to the owner, so it is a constant.
  bool get canViewAndExport => true;
}

/// Works out the standing from three facts: whether the shop ever paid, when
/// the next payment (or the end of the trial) falls due, and the time now.
LicenceStanding standingFor({
  required bool everPaid,
  required DateTime dueAt,
  required DateTime now,
  int graceDays = kGraceDays,
}) {
  final graceEnds = dueAt.add(Duration(days: graceDays));
  if (now.isBefore(dueAt)) {
    return LicenceStanding(
      status: everPaid ? LicenceStatus.active : LicenceStatus.trial,
      dueAt: dueAt,
      daysLeft: _ceilDays(dueAt.difference(now)),
    );
  }
  if (now.isBefore(graceEnds)) {
    return LicenceStanding(
      status: LicenceStatus.grace,
      dueAt: dueAt,
      daysLeft: _ceilDays(graceEnds.difference(now)),
    );
  }
  return LicenceStanding(
    status: LicenceStatus.salesPaused,
    dueAt: dueAt,
    daysLeft: 0,
  );
}

int _ceilDays(Duration d) => (d.inMinutes / (24 * 60)).ceil();
