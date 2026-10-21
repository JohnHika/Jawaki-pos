import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// Pure, unit-tested helpers for the Clients feature (and the Overview, which
/// reuses the version and status helpers). No widgets, no I/O.

// ------------------------------------------------------------ status filters

/// One chip on the Clients list. `value == null` means "All".
class StatusFilter {
  const StatusFilter(this.label, this.value);
  final String label;
  final String? value;
}

/// The subscription statuses the API accepts as a `status` filter.
const List<StatusFilter> kStatusFilters = [
  StatusFilter('All', null),
  StatusFilter('Active', 'ACTIVE'),
  StatusFilter('Trial', 'TRIAL'),
  StatusFilter('Past due', 'PAST_DUE'),
  StatusFilter('Suspended', 'SUSPENDED'),
  StatusFilter('Cancelled', 'CANCELLED'),
];

/// Accepts "past_due", "PAST_DUE", " Active " ... and returns the canonical API
/// value, or null (= All) for anything that is not a known status.
String? normalizeStatus(String? raw) {
  final s = raw?.trim().toUpperCase().replaceAll(' ', '_');
  if (s == null || s.isEmpty) return null;
  for (final f in kStatusFilters) {
    if (f.value == s) return s;
  }
  return null;
}

/// Index of the chip for [status] in [kStatusFilters] (0 = All).
int statusFilterIndex(String? status) {
  final s = normalizeStatus(status);
  final i = kStatusFilters.indexWhere((f) => f.value == s);
  return i < 0 ? 0 : i;
}

String statusFilterLabel(String? status) => kStatusFilters[statusFilterIndex(status)].label;

// ------------------------------------------------------------------ wording

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

/// "27 companies", "1 company", "3 companies found" when a search/filter is on.
String companyCountLabel(int total, {bool filtered = false}) =>
    '${plural(total, 'company', 'companies')}${filtered ? ' found' : ''}';

/// Seat limits at or above this are the backend's stand-in for "unlimited".
const int kUnlimitedSeats = 999999;

String seatsLabel(int used, int max) =>
    max >= kUnlimitedSeats ? '$used (no limit)' : '$used of $max';

bool seatsFull(int used, int max) => max > 0 && max < kUnlimitedSeats && used >= max;

/// A company on the TRIAL plan is also in the TRIAL status: show one pill, not two.
bool planRepeatsStatus(String plan, String? status) => status != null && plan.trim().toUpperCase() == status.trim().toUpperCase();

// ----------------------------------------------------------- subscription end

/// Colour for the "5 days left / 3 days overdue" line on a company.
/// Overdue is danger, the last week is a warning, everything else is calm.
Tone endTone(DateTime? end, {DateTime? now}) {
  if (end == null) return Tone.neutral;
  final n = now ?? DateTime.now();
  final days = DateTime(end.toLocal().year, end.toLocal().month, end.toLocal().day)
      .difference(DateTime(n.year, n.month, n.day))
      .inDays;
  if (days < 0) return Tone.danger;
  if (days <= 7) return Tone.warning;
  return Tone.neutral;
}

/// Mirrors the backend: an extension counts from the current end, or from now
/// when the subscription has already lapsed.
DateTime projectedPeriodEnd(DateTime? currentEnd, int days, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final base = currentEnd != null && currentEnd.isAfter(n) ? currentEnd : n;
  return base.add(Duration(days: days));
}

/// "Extend by" input: whole days from 1 to 365, otherwise null.
int? parseExtendDays(String input) {
  final n = int.tryParse(input.trim());
  if (n == null || n < 1 || n > 365) return null;
  return n;
}

/// Credit amount typed by staff ("1,500", "250.50"). The API needs at least KES 1.
num? parseKesAmount(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return null;
  final n = num.tryParse(cleaned);
  if (n == null || n.isNaN || n.isInfinite || n < 1) return null;
  final rounded = (n * 100).round() / 100;
  return rounded == rounded.roundToDouble() ? rounded.round() : rounded;
}

// ------------------------------------------------------------------- versions

/// Compares app versions like "1.0.74", "v1.2", "1.0.74+3" numerically per
/// segment ("1.0.9" < "1.0.74"). Missing segments count as 0.
int compareVersions(String a, String b) {
  List<String> parts(String v) =>
      v.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+\-_]')).where((s) => s.isNotEmpty).toList();
  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final sa = i < pa.length ? pa[i] : '0';
    final sb = i < pb.length ? pb[i] : '0';
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    final c = (na != null && nb != null) ? na.compareTo(nb) : sa.compareTo(sb);
    if (c != 0) return c < 0 ? -1 : 1;
  }
  return 0;
}

bool _knownVersion(String? v) {
  if (v == null) return false;
  final t = v.trim().toLowerCase();
  return t.isNotEmpty && t != 'unknown';
}

/// Highest version in [versions]; null when none is known.
String? newestVersion(Iterable<String?> versions) {
  String? best;
  for (final v in versions) {
    if (!_knownVersion(v)) continue;
    if (best == null || compareVersions(v!, best) > 0) best = v;
  }
  return best;
}

/// True when [version] is known and older than [newest] (the newest among the
/// same company's devices). Unknown versions are never flagged.
bool isOutdatedVersion(String? version, String? newest) {
  if (!_knownVersion(version) || !_knownVersion(newest)) return false;
  return compareVersions(version!, newest!) < 0;
}

// ---------------------------------------------------------------- list paging

/// Appends [incoming] to [existing] without duplicates (a company created while
/// the user scrolls shifts the pages, which would otherwise repeat a row).
List<T> mergePage<T>(List<T> existing, List<T> incoming, String Function(T) idOf) {
  final seen = existing.map(idOf).toSet();
  return [...existing, ...incoming.where((e) => seen.add(idOf(e)))];
}

/// Pinned notes first, newest first inside each group.
List<TenantNote> sortNotes(List<TenantNote> notes) {
  final copy = [...notes];
  copy.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ta = a.createdAt?.millisecondsSinceEpoch ?? 0;
    final tb = b.createdAt?.millisecondsSinceEpoch ?? 0;
    return tb.compareTo(ta);
  });
  return copy;
}

// --------------------------------------------------------------------- tones

/// Company-role colour (the roles a company gives its own staff).
Tone companyRoleTone(String role) {
  switch (role.toUpperCase()) {
    case 'ADMIN':
    case 'OWNER':
      return Tone.brand;
    case 'MANAGER':
      return Tone.info;
    case 'SUPERVISOR':
      return Tone.warning;
    default:
      return Tone.neutral;
  }
}

Tone invoiceTone(String status) {
  switch (status.toUpperCase()) {
    case 'PAID':
      return Tone.success;
    case 'PENDING':
      return Tone.warning;
    default:
      return Tone.neutral;
  }
}

Tone activationTone(String? status) {
  switch (status?.toUpperCase()) {
    case 'PAID':
      return Tone.success;
    case 'PENDING':
      return Tone.warning;
    default:
      return Tone.neutral;
  }
}

/// Goodwill credits are stored as invoices whose reference reads `CREDIT:<reason>`.
String? creditReason(Invoice i) {
  final ref = i.reference;
  if (ref == null || !ref.toUpperCase().startsWith('CREDIT:')) return null;
  final reason = ref.substring('CREDIT:'.length).trim();
  return reason.isEmpty ? null : reason;
}

/// "M-Pesa", "Paystack", "Credit"... for the provider codes the API returns.
String providerLabel(String? provider) {
  switch (provider?.toUpperCase()) {
    case null:
    case '':
      return '—';
    case 'MPESA':
    case 'MPESA_MANUAL':
      return 'M-Pesa';
    case 'PAYSTACK':
      return 'Paystack';
    case 'CREDIT':
      return 'Credit';
    default:
      final s = provider!.replaceAll('_', ' ').toLowerCase();
      return s[0].toUpperCase() + s.substring(1);
  }
}

// ------------------------------------------------------------------- actions

enum TenantAction { extend, suspend, reactivate, credit, forceLogout, lockOut, liftLockout }

/// The actions the signed-in role may run on a company right now, in menu order.
/// The server still enforces every one of them; this only decides what to show.
List<TenantAction> availableActions({
  required bool Function(String permission) can,
  required String? subscriptionStatus,
  required bool isActive,
}) {
  final status = subscriptionStatus?.toUpperCase();
  final lapsed = status == 'SUSPENDED' || status == 'CANCELLED';
  return [
    if (can(Perm.tenantsManage)) TenantAction.extend,
    if (can(Perm.tenantsSuspend)) lapsed ? TenantAction.reactivate : TenantAction.suspend,
    if (can(Perm.billingManage)) TenantAction.credit,
    if (can(Perm.tenantsSecurity)) TenantAction.forceLogout,
    if (can(Perm.tenantsSecurity)) isActive ? TenantAction.lockOut : TenantAction.liftLockout,
  ];
}
