import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

/// Pure helpers for the Security centre and the Audit log (no network), kept
/// small and separate so the display rules can be unit-tested.

// ----------------------------------------------------------------- categories

/// The category filter chips of the audit log: (API value, label).
const List<(String?, String)> auditCategoryFilters = [
  (null, 'All'),
  ('AUTH', 'Sign-in'),
  ('TEAM', 'Team'),
  ('TENANT', 'Companies'),
  ('BILLING', 'Billing'),
  ('LICENSE', 'Licences'),
  ('SECURITY', 'Security'),
];

/// The severity filter chips: (API value, label).
const List<(String?, String)> auditSeverityFilters = [
  (null, 'All'),
  ('WARN', 'Warnings'),
  ('CRITICAL', 'Critical'),
];

String categoryLabel(String category) {
  for (final (value, label) in auditCategoryFilters) {
    if (value == category) return label;
  }
  return Fmt.label(category);
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'AUTH':
      return Icons.login_rounded;
    case 'TEAM':
      return Icons.groups_rounded;
    case 'TENANT':
      return Icons.storefront_rounded;
    case 'BILLING':
      return Icons.payments_rounded;
    case 'LICENSE':
      return Icons.verified_user_outlined;
    case 'SECURITY':
      return Icons.shield_rounded;
  }
  return Icons.history_rounded;
}

// ------------------------------------------------------------------ severity

Tone severityTone(String severity) => StatusTone.severity(severity);

String severityLabel(String severity) {
  switch (severity) {
    case 'CRITICAL':
      return 'Critical';
    case 'WARN':
      return 'Warning';
    case 'INFO':
      return 'Info';
  }
  return Fmt.label(severity);
}

/// Only WARN and CRITICAL get a pill; INFO is the quiet default.
bool showSeverityPill(String severity) => severity == 'WARN' || severity == 'CRITICAL';

/// Two-factor coverage: fully covered is good, none at all is an alarm,
/// anything in between needs attention.
Tone coverageTone(int percent) {
  if (percent >= 100) return Tone.success;
  if (percent <= 0) return Tone.danger;
  return Tone.warning;
}

// -------------------------------------------------------------------- actions

const Map<String, String> _actionOverrides = {
  'AUTH_LOGIN_FAILED_UNKNOWN': 'Sign-in failed (unknown account)',
  'AUTH_LOGIN_DISABLED_ACCOUNT': 'Sign-in on a disabled account',
  'AUTH_LOGIN_BLOCKED_LOCKED': 'Sign-in blocked (account locked)',
  'AUTH_2FA_FAILED': 'Two-step code rejected',
  'AUTH_REFRESH_TOKEN_REUSE': 'Refresh token reused',
};

const Map<String, String> _actionWords = {
  'LOGIN': 'sign-in',
  'LOGOUT': 'sign-out',
  '2FA': 'two-step',
  'TENANT': 'company',
  'LICENSE': 'licence',
  'MPESA': 'M-Pesa',
};

/// Categories whose prefix adds nothing once the category is shown next to it.
const Set<String> _redundantPrefixes = {'AUTH', 'TEAM', 'SECURITY', 'BILLING'};

/// "PLATFORM_ADMIN_TENANT_EXTENDED" -> "Company extended",
/// "AUTH_LOGIN_SUCCESS" -> "Sign-in success".
String prettifyAction(String? action) {
  final raw = action?.trim().toUpperCase() ?? '';
  if (raw.isEmpty) return 'Unknown action';
  final override = _actionOverrides[raw];
  if (override != null) return override;

  var tokens = raw.split('_').where((t) => t.isNotEmpty).toList();
  if (tokens.length > 2 && tokens[0] == 'PLATFORM' && tokens[1] == 'ADMIN') {
    tokens = tokens.sublist(2);
  }
  if (tokens.length > 1 && _redundantPrefixes.contains(tokens.first)) {
    tokens = tokens.sublist(1);
  }
  final text = tokens.map((t) => _actionWords[t] ?? t.toLowerCase()).join(' ');
  return text[0].toUpperCase() + text.substring(1);
}

/// What the row headline says: the server's summary, or the action as a fallback.
String entryTitle(AuditEntry entry) {
  final s = entry.summary?.trim();
  return (s == null || s.isEmpty) ? prettifyAction(entry.action) : s;
}

/// "admin@x.com · Admin", or a plain explanation when nobody was signed in.
String actorLine(AuditEntry entry) {
  final email = entry.actorEmail?.trim();
  if (email == null || email.isEmpty) return 'No staff account';
  final role = entry.actorRole;
  return (role == null || role.isEmpty) ? email : '$email · ${Fmt.label(role)}';
}

/// Short, readable device text from a long user-agent string.
String? trimUserAgent(String? userAgent, {int max = 90}) {
  final ua = userAgent?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (ua == null || ua.isEmpty) return null;
  return ua.length <= max ? ua : '${ua.substring(0, max - 1).trimRight()}…';
}

/// "unlocks in 12 min" / "unlock due" / "locked".
String unlockLabel(DateTime? until, {DateTime? now}) {
  if (until == null) return 'locked';
  final n = now ?? DateTime.now();
  if (!until.isAfter(n)) return 'unlock due';
  return 'unlocks ${Fmt.ago(until, now: n)}';
}

// --------------------------------------------------------------- grouping

/// "Today", "Yesterday", otherwise the date. Unknown dates read "Unknown date".
String dayLabel(DateTime? day, {DateTime? now}) {
  if (day == null) return 'Unknown date';
  final n = now ?? DateTime.now();
  final d = day.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return Fmt.date(d);
}

/// One row in the audit list: a day header or an entry.
class AuditRow {
  const AuditRow.header(String this.header) : entry = null;
  const AuditRow.entry(AuditEntry this.entry) : header = null;

  final String? header;
  final AuditEntry? entry;

  bool get isHeader => header != null;
}

/// Flattens [entries] (newest first) into rows with a header before each
/// local calendar day. Entries without a date are collected under
/// "Unknown date" at the end. Order within a day is preserved.
List<AuditRow> buildAuditRows(List<AuditEntry> entries, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final rows = <AuditRow>[];
  final undated = <AuditEntry>[];
  DateTime? currentDay;

  for (final e in entries) {
    final at = e.createdAt?.toLocal();
    if (at == null) {
      undated.add(e);
      continue;
    }
    final day = DateTime(at.year, at.month, at.day);
    if (currentDay == null || day != currentDay) {
      currentDay = day;
      rows.add(AuditRow.header(dayLabel(day, now: n)));
    }
    rows.add(AuditRow.entry(e));
  }
  if (undated.isNotEmpty) {
    rows.add(AuditRow.header(dayLabel(null)));
    rows.addAll(undated.map(AuditRow.entry));
  }
  return rows;
}

// --------------------------------------------------------------- metadata

/// A label/value pair ready to render in the detail sheet.
class MetaPair {
  const MetaPair(this.label, this.value);
  final String label;
  final String value;

  @override
  bool operator ==(Object other) => other is MetaPair && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);

  @override
  String toString() => '$label: $value';
}

const Map<String, String> _keyWords = {
  'kes': 'KES',
  'ip': 'IP',
  'id': 'ID',
  'ids': 'IDs',
  'url': 'URL',
  'mpesa': 'M-Pesa',
};

/// "twoFactor" / "two_factor" -> "Two factor", "amountKes" -> "Amount KES".
String humanizeKey(String key) {
  final spaced = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[_\-.]+'), ' ')
      .trim();
  if (spaced.isEmpty) return key;
  final words = spaced.split(RegExp(r'\s+')).map((w) {
    final lower = w.toLowerCase();
    return _keyWords[lower] ?? lower;
  }).toList();
  final first = words.first;
  words[0] = _keyWords.containsValue(first) ? first : first[0].toUpperCase() + first.substring(1);
  return words.join(' ');
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$');

/// A single metadata value as people read it: booleans as Yes/No, ISO dates as
/// local date-times, amounts under a `...Kes` key as KES.
String formatMetadataValue(Object? value, {String key = ''}) {
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) {
    return key.toLowerCase().endsWith('kes') ? Fmt.kes(value) : value.toString();
  }
  if (value is String) {
    if (_isoDate.hasMatch(value)) {
      final d = DateTime.tryParse(value);
      if (d != null) return Fmt.dateTime(d);
    }
    return value;
  }
  return value.toString();
}

bool _isScalar(Object? v) => v is String || v is num || v is bool;

/// Turns audit metadata into readable label/value rows. Nested maps become
/// "Parent › Child" rows, scalar lists are comma-joined, nulls and empty
/// values are dropped. Anything nested deeper than [maxDepth] (or a list of
/// objects) falls back to compact JSON so no information is lost.
List<MetaPair> flattenMetadata(Map<String, dynamic>? metadata, {int maxDepth = 3}) {
  final out = <MetaPair>[];

  void walk(Object? value, List<String> path) {
    final key = path.last;
    final label = path.map(humanizeKey).join(' › ');
    if (value == null) return;
    if (value is Map) {
      if (path.length >= maxDepth) {
        if (value.isNotEmpty) out.add(MetaPair(label, jsonEncode(value)));
        return;
      }
      for (final e in value.entries) {
        walk(e.value, [...path, e.key.toString()]);
      }
      return;
    }
    if (value is List) {
      if (value.isEmpty) return;
      if (value.every(_isScalar)) {
        out.add(MetaPair(label, value.map((v) => formatMetadataValue(v, key: key)).join(', ')));
      } else {
        out.add(MetaPair(label, jsonEncode(value)));
      }
      return;
    }
    if (value is String && value.trim().isEmpty) return;
    out.add(MetaPair(label, formatMetadataValue(value, key: key)));
  }

  (metadata ?? const <String, dynamic>{}).forEach((k, v) => walk(v, [k]));
  return out;
}

/// "PlatformAdmin" -> "Platform admin" for the audit target type.
String prettifyTargetType(String? type) {
  final t = type?.trim() ?? '';
  return t.isEmpty ? '—' : humanizeKey(t);
}
