import '../../data/models.dart';
import 'tenants_logic.dart' show kUnlimitedSeats;

/// Licence model + diffing for the licence editor. Mirrors the backend
/// (`license.catalog.ts` -> ResolvedLicense, `UpdateTenantLicenseDto`).

enum FeatureChoice { planDefault, grant, revoke }

const List<String> kEnforcementModes = ['off', 'warn', 'enforce'];

String enforcementLabel(String mode) {
  switch (mode) {
    case 'warn':
      return 'Warn';
    case 'enforce':
      return 'Enforce';
    default:
      return 'Off';
  }
}

/// One-line explanation shown under the segmented control.
String enforcementExplain(String mode) {
  switch (mode) {
    case 'warn':
      return 'Nothing is blocked, but every would-be block is logged for you to review.';
    case 'enforce':
      return 'Modules the licence does not include, seats over the limit and an expired licence are refused.';
    default:
      return 'Nothing is blocked. The licence is only reported.';
  }
}

/// Wording for the modules (mirrors FEATURE_LABELS on the server); unknown keys
/// fall back to a readable version of the key.
String featureLabel(String key) {
  switch (key) {
    case 'analytics':
      return 'Sales analytics';
    case 'customReports':
      return 'Custom reports and exports';
    case 'aiAssistant':
      return 'Axon AI assistant';
    case 'multiCurrency':
      return 'Multi-currency';
    case 'prioritySupport':
      return 'Priority support';
  }
  final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}').toLowerCase();
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

class LicenseFeatureView {
  const LicenseFeatureView({required this.allowed, required this.source});
  final bool allowed;

  /// `plan` (follows the price list) or `override` (set by an operator).
  final String source;
  bool get isOverride => source == 'override';

  FeatureChoice get choice =>
      !isOverride ? FeatureChoice.planDefault : (allowed ? FeatureChoice.grant : FeatureChoice.revoke);
}

class LicenseView {
  const LicenseView({
    required this.plan,
    required this.enforcement,
    required this.features,
    required this.maxBranches,
    required this.maxUsers,
    required this.validUntil,
    required this.expired,
    required this.licenseKey,
    required this.note,
    required this.unknownPlan,
  });

  final String plan;
  final String enforcement; // off | warn | enforce
  final Map<String, LicenseFeatureView> features; // server order
  final int maxBranches;
  final int maxUsers;
  final DateTime? validUntil;
  final bool expired;
  final String? licenseKey;
  final String? note;
  final bool unknownPlan;

  bool get enforced => enforcement == 'enforce';

  /// The server reports "unlimited" as a huge number; the editor shows that as an empty field.
  int? get editableMaxBranches => maxBranches >= kUnlimitedSeats ? null : maxBranches;
  int? get editableMaxUsers => maxUsers >= kUnlimitedSeats ? null : maxUsers;

  factory LicenseView.fromJson(Map<String, dynamic> j) {
    final limits = J.map(j['limits']);
    final mode = J.s(j['enforcement'], 'off');
    return LicenseView(
      plan: J.s(j['plan']),
      enforcement: kEnforcementModes.contains(mode) ? mode : 'off',
      features: {
        for (final e in J.map(j['features']).entries)
          e.key: LicenseFeatureView(
            allowed: J.b(J.map(e.value)['allowed']),
            source: J.s(J.map(e.value)['source'], 'plan'),
          ),
      },
      maxBranches: J.i(limits['maxBranches']),
      maxUsers: J.i(limits['maxUsers']),
      validUntil: J.d(j['validUntil']),
      expired: J.b(j['expired']),
      licenseKey: J.sn(j['licenseKey']),
      note: J.sn(j['note']),
      unknownPlan: J.b(j['unknownPlan']),
    );
  }

  /// Short status for a module on the summary card.
  String featureStatus(String key) {
    final f = features[key];
    if (f == null) return '';
    if (f.isOverride) return f.allowed ? 'granted' : 'revoked';
    return f.allowed ? 'in plan' : 'not in plan';
  }
}

/// What the editor holds while staff are typing. Limits are nullable ints; an
/// empty field means "no explicit limit".
class LicenseDraft {
  const LicenseDraft({
    required this.enforcement,
    required this.choices,
    required this.validUntil,
    required this.maxBranches,
    required this.maxUsers,
    required this.note,
    required this.reissueKey,
  });

  final String enforcement;
  final Map<String, FeatureChoice> choices;
  final DateTime? validUntil;
  final int? maxBranches;
  final int? maxUsers;
  final String note;
  final bool reissueKey;

  factory LicenseDraft.from(LicenseView v) => LicenseDraft(
        enforcement: v.enforcement,
        choices: {for (final e in v.features.entries) e.key: e.value.choice},
        validUntil: v.validUntil,
        maxBranches: v.editableMaxBranches,
        maxUsers: v.editableMaxUsers,
        note: v.note ?? '',
        reissueKey: false,
      );

  LicenseDraft copyWith({
    String? enforcement,
    Map<String, FeatureChoice>? choices,
    DateTime? validUntil,
    bool clearValidUntil = false,
    int? maxBranches,
    bool clearMaxBranches = false,
    int? maxUsers,
    bool clearMaxUsers = false,
    String? note,
    bool? reissueKey,
  }) =>
      LicenseDraft(
        enforcement: enforcement ?? this.enforcement,
        choices: choices ?? this.choices,
        validUntil: clearValidUntil ? null : (validUntil ?? this.validUntil),
        maxBranches: clearMaxBranches ? null : (maxBranches ?? this.maxBranches),
        maxUsers: clearMaxUsers ? null : (maxUsers ?? this.maxUsers),
        note: note ?? this.note,
        reissueKey: reissueKey ?? this.reissueKey,
      );
}

/// Result of reading a limit text field.
class LimitInput {
  const LimitInput(this.value, {this.valid = true});
  final int? value; // null = empty
  final bool valid;
}

/// Empty is allowed (clears the explicit limit); otherwise a whole number >= 1.
LimitInput parseLimit(String text) {
  final t = text.trim();
  if (t.isEmpty) return const LimitInput(null);
  final n = int.tryParse(t);
  if (n == null || n < 1) return const LimitInput(null, valid: false);
  return LimitInput(n);
}

const int kLicenseNoteMax = 500;

String? _normNote(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

bool _sameInstant(DateTime? a, DateTime? b) {
  if (a == null || b == null) return a == b;
  return a.isAtSameMomentAs(b);
}

/// The PUT body: ONLY what changed. Overrides carry `true` (grant), `false`
/// (revoke) or `null` (back to the plan's default), exactly as the DTO expects.
Map<String, dynamic> buildLicensePatch(LicenseView original, LicenseDraft draft) {
  final patch = <String, dynamic>{};

  if (draft.enforcement != original.enforcement) patch['enforcement'] = draft.enforcement;

  final overrides = <String, dynamic>{};
  for (final e in original.features.entries) {
    final chosen = draft.choices[e.key] ?? e.value.choice;
    if (chosen == e.value.choice) continue;
    overrides[e.key] = switch (chosen) {
      FeatureChoice.grant => true,
      FeatureChoice.revoke => false,
      FeatureChoice.planDefault => null,
    };
  }
  if (overrides.isNotEmpty) patch['overrides'] = overrides;

  if (!_sameInstant(original.validUntil, draft.validUntil)) {
    patch['validUntil'] = draft.validUntil?.toUtc().toIso8601String();
  }
  if (draft.maxBranches != original.editableMaxBranches) patch['maxBranches'] = draft.maxBranches;
  if (draft.maxUsers != original.editableMaxUsers) patch['maxUsers'] = draft.maxUsers;
  if (_normNote(draft.note) != _normNote(original.note)) patch['note'] = _normNote(draft.note);
  if (draft.reissueKey) patch['reissueKey'] = true;
  return patch;
}

/// Number of distinct edits in [patch] (an `overrides` map counts per module).
int licenseChangeCount(Map<String, dynamic> patch) {
  var n = 0;
  for (final e in patch.entries) {
    n += e.key == 'overrides' ? (e.value as Map).length : 1;
  }
  return n;
}
