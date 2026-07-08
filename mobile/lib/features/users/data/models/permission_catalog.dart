/// One granular permission key from the backend catalog, e.g.
/// `sales.void` — grouped by [feature] for the role editor / override
/// screens' accordion rendering.
class PermissionDef {
  final String key;
  final String feature;
  final String action;
  final String label;
  final String? description;

  const PermissionDef({
    required this.key,
    required this.feature,
    required this.action,
    required this.label,
    this.description,
  });

  factory PermissionDef.fromJson(Map<String, dynamic> json) {
    return PermissionDef(
      key: json['key'] as String,
      feature: json['feature'] as String,
      action: json['action'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
    );
  }
}

/// One feature group from `GET /v1/permissions`, e.g. all `sales.*` keys
/// bundled under feature "sales".
class PermissionFeatureGroup {
  final String feature;
  final List<PermissionDef> permissions;

  const PermissionFeatureGroup({required this.feature, required this.permissions});

  factory PermissionFeatureGroup.fromJson(Map<String, dynamic> json) {
    return PermissionFeatureGroup(
      feature: json['feature'] as String,
      permissions: (json['permissions'] as List<dynamic>)
          .map((p) => PermissionDef.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Human-friendly section heading, e.g. "cash_flow" -> "Cash Flow".
  String get displayName => feature
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

List<PermissionFeatureGroup> parsePermissionCatalog(List<dynamic> raw) {
  return raw
      .map((g) => PermissionFeatureGroup.fromJson(g as Map<String, dynamic>))
      .toList();
}
