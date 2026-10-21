import 'dart:math' as math;

import '../../core/theme.dart';
import '../../data/models.dart';
import '../tenants/tenants_logic.dart';

/// Pure helpers behind the Overview screen. No widgets, no I/O.

// ------------------------------------------------------------------ greeting

/// "Good morning" until noon, "Good afternoon" until 17:00, then "Good evening".
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "Amina Wanjiku" -> "Amina"; null/blank -> null.
String? firstNameOf(String? fullName) {
  final parts = (fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? null : parts.first;
}

/// "Good morning, Amina" (or just "Good morning" when the name is unknown).
String greetingLine(String? fullName, DateTime now) {
  final first = firstNameOf(fullName);
  final g = greetingFor(now);
  return first == null ? g : '$g, $first';
}

// ------------------------------------------------------------- revenue delta

/// "+12%", "−92%", "0%". Under 10% one decimal is kept ("+3.4%").
String formatDelta(double pct) {
  final a = pct.abs();
  if (a < 0.05) return '0%';
  final sign = pct > 0 ? '+' : '−';
  if (a >= 1000) return '${sign}999%+';
  final body = a < 10 ? a.toStringAsFixed(1) : a.round().toString();
  return '$sign$body%';
}

/// Green when collections grew, red when they fell, neutral when flat.
Tone deltaTone(double pct) {
  if (pct.abs() < 0.05) return Tone.neutral;
  return pct > 0 ? Tone.success : Tone.danger;
}

// ------------------------------------------------------------ status tiles

class OverviewStatusTile {
  const OverviewStatusTile(this.status, this.label, this.tone);
  final String status; // API value, also the Clients filter
  final String label;
  final Tone tone;
}

const List<OverviewStatusTile> kOverviewStatusTiles = [
  OverviewStatusTile('ACTIVE', 'Active', Tone.success),
  OverviewStatusTile('TRIAL', 'Trial', Tone.info),
  OverviewStatusTile('PAST_DUE', 'Past due', Tone.warning),
  OverviewStatusTile('SUSPENDED', 'Suspended', Tone.danger),
];

// ----------------------------------------------------------------- the chart

/// Chart ceiling and grid step, rounded to "nice" numbers (1, 2, 2.5, 5 x 10^n)
/// so the axis reads 0 / 10K / 20K / 30K / 40K rather than 0 / 9.55K / ...
class AxisScale {
  const AxisScale(this.max, this.interval);
  final double max;
  final double interval;
}

AxisScale niceAxis(num maxValue, {int targetLines = 4}) {
  if (maxValue <= 0 || maxValue.isNaN || maxValue.isInfinite) return const AxisScale(1, 1);
  final raw = maxValue / targetLines;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final normalized = raw / magnitude;
  final nice = normalized <= 1
      ? 1
      : normalized <= 2
          ? 2
          : normalized <= 2.5
              ? 2.5
              : normalized <= 5
                  ? 5
                  : 10;
  final step = nice * magnitude;
  return AxisScale((maxValue / step).ceil() * step, step);
}

/// Axis label without a currency prefix: 0, 500, 2.5K, 40K, 1.2M.
String compactAmount(num v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  String trim(double x) => x == x.roundToDouble() ? x.toStringAsFixed(0) : x.toStringAsFixed(1);
  if (a >= 1000000) return '$sign${trim(a / 1000000)}M';
  if (a >= 1000) return '$sign${trim(a / 1000)}K';
  return '$sign${a.round()}';
}

/// True when at least one of the months has money in it.
bool hasRevenue(List<MonthRevenue> months) => months.any((m) => m.amountKes > 0);

num revenueTotal(List<MonthRevenue> months) => months.fold<num>(0, (a, m) => a + m.amountKes);

// ----------------------------------------------------------------- fleet bars

class VersionShare {
  const VersionShare({required this.version, required this.devices, required this.fraction, required this.latest});
  final String version;
  final int devices;

  /// Bar length 0..1 relative to the most common version.
  final double fraction;
  final bool latest;

  bool get unknown => version.toLowerCase() == 'unknown';
}

class VersionBreakdown {
  const VersionBreakdown({
    required this.shown,
    required this.otherVersions,
    required this.otherDevices,
    required this.behindLatest,
    required this.latest,
  });

  final List<VersionShare> shown;

  /// Versions (and their devices) folded into "other" past the display limit.
  final int otherVersions;
  final int otherDevices;

  /// Devices on a known version older than [latest].
  final int behindLatest;
  final String? latest;
}

/// Most-used versions first. Anything past [limit] is folded into one tail row.
VersionBreakdown versionBreakdown(Map<String, int> versions, {int limit = 6}) {
  final entries = versions.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      if (c != 0) return c;
      // Ties: newest known version first, "unknown" last.
      final au = a.key.toLowerCase() == 'unknown';
      final bu = b.key.toLowerCase() == 'unknown';
      if (au != bu) return au ? 1 : -1;
      return compareVersions(b.key, a.key);
    });
  final latest = newestVersion(entries.map((e) => e.key));
  final peak = entries.isEmpty ? 1 : entries.first.value;
  final head = entries.take(limit).toList();
  final tail = entries.skip(limit).toList();
  return VersionBreakdown(
    shown: [
      for (final e in head)
        VersionShare(version: e.key, devices: e.value, fraction: e.value / peak, latest: e.key == latest),
    ],
    otherVersions: tail.length,
    otherDevices: tail.fold<int>(0, (a, e) => a + e.value),
    behindLatest: entries.where((e) => isOutdatedVersion(e.key, latest)).fold<int>(0, (a, e) => a + e.value),
    latest: latest,
  );
}

/// "Fleet active" percentage for the caption, null when there are no devices.
int? activePercent(int active, int total) => total <= 0 ? null : ((active / total) * 100).round().clamp(0, 100);
