import 'dart:convert';

import '../providers/business_layout_provider.dart';

/// Matches the product fields enabled by a shop's business layout.
///
/// Product metadata is stored as JSON in the local catalog. Supporting both
/// decoded API maps and the cached JSON string keeps the same search behavior
/// in POS, favourites, and the catalogue screen.
bool businessLayoutProductMatchesSearch({
  required String name,
  required String code,
  required Object? metadata,
  required BusinessLayoutConfig layout,
  required String query,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  if (name.toLowerCase().contains(normalizedQuery) ||
      code.toLowerCase().contains(normalizedQuery)) {
    return true;
  }

  final industryFields = _industryFieldsFromMetadata(metadata);
  if (industryFields == null) return false;
  return layout.effectiveProductFields.any((field) {
    final value = industryFields[field.key]?.toString().trim();
    return value != null && value.toLowerCase().contains(normalizedQuery);
  });
}

Map<dynamic, dynamic>? _industryFieldsFromMetadata(Object? metadata) {
  Object? decoded = metadata;
  if (metadata is String && metadata.trim().isNotEmpty) {
    try {
      decoded = jsonDecode(metadata);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final industryFields = decoded['industryFields'];
  return industryFields is Map ? industryFields : null;
}
