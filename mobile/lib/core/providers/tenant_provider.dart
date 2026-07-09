import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';

/// Single source of truth for "whose workspace is this" — the tenant's
/// display name/logo and the logged-in user's name. Consolidates fallback
/// chains that used to be copy-pasted (and drifting) across the PIN screen,
/// dashboard greeting, and AI chat context builder.
class TenantIdentity {
  final String companyName;
  final String? logoUrl;
  final String userFirstName;
  final String userFullName;
  final String branchName;
  final String role;

  const TenantIdentity({
    required this.companyName,
    required this.logoUrl,
    required this.userFirstName,
    required this.userFullName,
    required this.branchName,
    required this.role,
  });

  static const empty = TenantIdentity(
    companyName: 'Your Company',
    logoUrl: null,
    userFirstName: '',
    userFullName: '',
    branchName: '',
    role: '',
  );
}

String? _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

Map<String, dynamic>? _primaryBranch(dynamic branches, String? branchId) {
  if (branches is! List) return null;
  final list = branches.whereType<Map>().cast<Map<String, dynamic>?>();
  return list.firstWhere(
    (branch) => branchId != null && branch?['id'] == branchId,
    orElse: () => list.firstWhere(
      (branch) => branch?['isPrimary'] == true,
      orElse: () => null,
    ),
  );
}

final tenantIdentityProvider = Provider<TenantIdentity>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return TenantIdentity.empty;

  final tenant = user['tenant'];
  final tenantMap =
      tenant is Map<String, dynamic> ? tenant : <String, dynamic>{};
  final branchId = user['branchId']?.toString();
  final primaryBranch = _primaryBranch(user['branches'], branchId);

  final companyName = _firstNonEmpty([
        tenantMap['name'],
        user['tenantName'],
        user['companyName'],
        'Your Company',
      ]) ??
      'Your Company';

  final logoUrl = _firstNonEmpty([
    tenantMap['logoUrl'],
    tenantMap['logo'],
    user['tenantLogoUrl'],
    user['companyLogoUrl'],
  ]);

  final firstName = _firstNonEmpty([user['firstName']]) ?? '';
  final lastName = _firstNonEmpty([user['lastName']]) ?? '';
  final fullName =
      [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  final branchName = _firstNonEmpty([
        user['branchName'],
        primaryBranch?['name'],
      ]) ??
      '';

  return TenantIdentity(
    companyName: companyName,
    logoUrl: logoUrl,
    userFirstName: firstName,
    userFullName: fullName.isNotEmpty ? fullName : companyName,
    branchName: branchName,
    role: (user['role'] ?? '').toString(),
  );
});
