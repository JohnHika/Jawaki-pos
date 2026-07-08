import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../data/models/permission_catalog.dart';

/// Full permission catalog, grouped by feature — fetched once and reused
/// by both the role editor and the per-user override screen so the
/// "~130 keys grouped by feature" rendering logic lives in one place.
final permissionCatalogProvider =
    FutureProvider.autoDispose<List<PermissionFeatureGroup>>((ref) async {
  final raw = await getIt<ApiClient>().getPermissionCatalog();
  return parsePermissionCatalog(raw);
});

/// Tenant users with their assigned roles — backs the user management
/// list screen.
final managedUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await getIt<ApiClient>().getManagedUsers();
  return raw.cast<Map<String, dynamic>>();
});

/// Tenant roles (system-seeded + admin-created) — backs the role list and
/// editor screens, and the role picker in the user override screen.
final tenantRolesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await getIt<ApiClient>().getRoles();
  return raw.cast<Map<String, dynamic>>();
});

/// One user's permission breakdown: { roles, fromRoles, granted, revoked,
/// effective } — backs the per-user override screen.
final userPermissionBreakdownProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  return getIt<ApiClient>().getUserPermissionBreakdown(userId);
});
