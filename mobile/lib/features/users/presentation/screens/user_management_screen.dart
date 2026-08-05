import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/user_management_provider.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!permissions.canManageUsers) {
      return const Scaffold(
        appBar: BrandedAppBar(title: 'Users', showBackButton: true),
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Restricted',
          subtitle: 'You do not have permission to manage users.',
        ),
      );
    }

    final usersAsync = ref.watch(managedUsersProvider);

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Users',
        showBackButton: true,
        actions: [
          if (permissions.canManageRoles)
            IconButton(
              tooltip: 'Roles',
              icon: const Icon(Icons.badge_outlined),
              onPressed: () => context.push('/users/roles'),
            ),
          IconButton(
            tooltip: 'Invitations',
            icon: const Icon(Icons.mail_outline_rounded),
            onPressed: () => context.push('/users/invitations'),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(managedUsersProvider),
          ),
        ],
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load users',
          subtitle: err.toString(),
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(managedUsersProvider),
        ),
        data: (users) {
          final filtered = _query.isEmpty
              ? users
              : users.where((u) {
                  final name = '${u['firstName']} ${u['lastName']}'.toLowerCase();
                  final email = (u['email'] as String? ?? '').toLowerCase();
                  return name.contains(_query.toLowerCase()) ||
                      email.contains(_query.toLowerCase());
                }).toList();

          return PageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceBorder.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'No users found',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _UserCard(user: filtered[index]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? '';
    final isActive = user['isActive'] as bool? ?? true;
    final roles = (user['roles'] as List<dynamic>? ?? [])
        .map((r) => (r as Map<String, dynamic>)['name'] as String)
        .toList();

    return GroupedCard(
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        SettingsRow(
          icon: Icons.person_rounded,
          title: name.isEmpty ? email : name,
          subtitle: email,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isActive)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: StatusBadge(label: 'Inactive', color: DesignColors.error),
                ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () => context.push('/users/${user['id']}/permissions'),
        ),
        if (roles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: roles
                  .map((r) => StatusBadge(label: r, color: DesignColors.accent))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
