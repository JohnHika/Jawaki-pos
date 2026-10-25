import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:shelf/shelf.dart' as shelf;

import '../../database/app_database.dart';
import 'middleware.dart';

/// Current phone-server account permissions and branch assignment.
///
/// The signed token proves who logged in. This record is re-read for each
/// protected request so deactivated users, changed permissions, and branch
/// reassignment take effect before the token expires.
class ServerUserAccess {
  final String userId;
  final String tenantId;
  final String? branchId;
  final Set<String> permissions;

  const ServerUserAccess({
    required this.userId,
    required this.tenantId,
    required this.branchId,
    required this.permissions,
  });

  bool has(String permission) => permissions.contains(permission);

  static Future<ServerUserAccess?> load(
    AppDatabase db,
    shelf.Request request,
  ) async {
    final tokenUser = getAuthUser(request);
    final userId = tokenUser?['sub']?.toString();
    final tokenTenantId = tokenUser?['tenantId']?.toString();
    if (userId == null || userId.isEmpty || tokenTenantId == null) return null;

    final rows = await db.customSelect(
      'SELECT permissions_json, is_active, branch_id, tenant_id '
      'FROM server_users WHERE id = ?',
      variables: [Variable.withString(userId)],
    ).get();
    if (rows.isEmpty || rows.first.read<int>('is_active') != 1) return null;

    final tenantId = rows.first.read<String>('tenant_id');
    if (tenantId != tokenTenantId) return null;

    final permissions = <String>{};
    final permissionsJson = rows.first.readNullable<String>('permissions_json');
    if (permissionsJson != null) {
      try {
        final decoded = jsonDecode(permissionsJson);
        if (decoded is List) {
          permissions
              .addAll(decoded.map((permission) => permission.toString()));
        }
      } on FormatException {
        // A malformed permission set grants no capabilities.
      }
    }

    final rawBranchId = rows.first.readNullable<String>('branch_id')?.trim();
    return ServerUserAccess(
      userId: userId,
      tenantId: tenantId,
      branchId: rawBranchId == null || rawBranchId.isEmpty ? null : rawBranchId,
      permissions: permissions,
    );
  }
}
