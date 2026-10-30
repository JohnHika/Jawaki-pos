import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/local_staff_roles.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';

class LocalStaffScreen extends ConsumerStatefulWidget {
  const LocalStaffScreen({super.key});

  @override
  ConsumerState<LocalStaffScreen> createState() => _LocalStaffScreenState();
}

class _LocalStaffScreenState extends ConsumerState<LocalStaffScreen> {
  bool _saving = false;

  AuthService get _auth => getIt<AuthService>();

  @override
  Widget build(BuildContext context) {
    final isOwner = _auth.isLocalWorkspaceOwner;
    final accounts = _auth.localStaffAccounts.toList()
      ..sort((a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ));

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Staff on this device',
        showBackButton: true,
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Add staff member',
              onPressed: _saving ? null : () => _editStaff(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
      ),
      body: !isOwner
          ? const PageContainer(
              withScroll: true,
              child: _LocalStaffAccessCard(
                icon: Icons.lock_outline_rounded,
                title: 'Owner access required',
                message: 'Only this device’s workspace owner can manage staff.',
              ),
            )
          : PageContainer(
              padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.lg,
                DesignSpacing.lg,
                DesignSpacing.xxl,
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const _LocalStaffAccessCard(
                    icon: Icons.phonelink_lock_rounded,
                    title: 'Local access for this register',
                    message:
                        'Each person signs in with their own PIN and role. Device biometrics are turned off while staff profiles are active because the device cannot identify which enrolled person approved the prompt. Profiles and permissions stay on this device; they are not cloud accounts or invitations.',
                    footnote:
                        'Set up staff separately on every device that needs its own team.',
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Team members',
                          style: DesignType.display.copyWith(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? DesignColors.darkTextPrimary
                                    : DesignColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${accounts.length}',
                        style: DesignType.body.copyWith(
                          fontSize: 13,
                          color: DesignColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  if (accounts.isEmpty)
                    _EmptyLocalStaffCard(onAdd: _saving ? null : _editStaff)
                  else
                    ...accounts.map((account) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: DesignSpacing.sm,
                          ),
                          child: _StaffCard(
                            account: account,
                            saving: _saving,
                            onEdit: () => _editStaff(account: account),
                            onToggle: () => _toggleActive(account),
                          ),
                        )),
                  const SizedBox(height: DesignSpacing.md),
                  _RoleGuideCard(),
                ],
              ),
            ),
      floatingActionButton: isOwner && accounts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _editStaff(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add staff'),
            )
          : null,
    );
  }

  Future<void> _editStaff({Map<String, dynamic>? account}) async {
    final values = await _showStaffForm(account: account);
    if (values == null || !mounted) return;
    setState(() => _saving = true);
    try {
      if (account == null) {
        await _auth.createLocalStaffAccount(
          name: values['name'] as String,
          role: values['role'] as String,
          pin: values['pin'] as String,
        );
      } else {
        await _auth.updateLocalStaffAccount(
          userId: account['id'].toString(),
          name: values['name'] as String,
          role: values['role'] as String,
          isActive: account['isActive'] != false,
          pin: values['pin'] as String?,
        );
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(account == null
                ? 'Staff profile created on this device.'
                : 'Staff profile updated.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> account) async {
    final nextActive = account['isActive'] == false;
    setState(() => _saving = true);
    try {
      await _auth.updateLocalStaffAccount(
        userId: account['id'].toString(),
        name: account['name']?.toString() ?? '',
        role: account['role']?.toString() ?? '',
        isActive: nextActive,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(nextActive
                  ? 'Staff access enabled.'
                  : 'Staff access paused.')),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>?> _showStaffForm({
    Map<String, dynamic>? account,
  }) async {
    final nameController = TextEditingController(
      text: account?['name']?.toString() ?? '',
    );
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var selectedRole = LocalStaffRoles.permissionsFor(
              account?['role']?.toString() ?? '',
            ) !=
            null
        ? account!['role'].toString()
        : LocalStaffRoles.names.first;
    var obscurePin = true;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? DesignColors.darkSurface
          : DesignColors.surface,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            DesignSpacing.lg,
            DesignSpacing.sm,
            DesignSpacing.lg,
            MediaQuery.viewInsetsOf(context).bottom + DesignSpacing.lg,
          ),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    account == null ? 'Add team member' : 'Edit team member',
                    style: DesignType.display.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.xs),
                  Text(
                    'Their PIN identifies their profile when they unlock this register.',
                    style: DesignType.body.copyWith(
                      color: DesignColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) {
                      final name = value?.trim() ?? '';
                      if (name.length < 2) return 'Enter their name.';
                      return null;
                    },
                  ),
                  const SizedBox(height: DesignSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Access role',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: LocalStaffRoles.names
                        .map((role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() => selectedRole = value);
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: DesignSpacing.xs,
                      left: DesignSpacing.sm,
                    ),
                    child: Text(
                      LocalStaffRoles.descriptionFor(selectedRole),
                      style: DesignType.body.copyWith(
                        fontSize: 12,
                        color: DesignColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  TextFormField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    obscureText: obscurePin,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText:
                          account == null ? 'Staff PIN' : 'New PIN (optional)',
                      helperText: account == null
                          ? 'Choose 4–6 digits. Keep it private.'
                          : 'Leave blank to keep the current PIN.',
                      prefixIcon: const Icon(Icons.pin_outlined),
                      suffixIcon: IconButton(
                        tooltip: obscurePin ? 'Show PIN' : 'Hide PIN',
                        onPressed: () => setModalState(
                          () => obscurePin = !obscurePin,
                        ),
                        icon: Icon(obscurePin
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: (value) {
                      final pin = value ?? '';
                      if (account == null || pin.isNotEmpty) {
                        if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                          return 'Enter 4–6 digits.';
                        }
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: confirmController,
                    keyboardType: TextInputType.number,
                    obscureText: obscurePin,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      prefixIcon: Icon(Icons.verified_user_outlined),
                    ),
                    validator: (value) {
                      final pin = pinController.text;
                      if (account == null || pin.isNotEmpty) {
                        if (value != pin) return 'PINs do not match.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  FilledButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.of(sheetContext).pop(<String, dynamic>{
                        'name': nameController.text.trim(),
                        'role': selectedRole,
                        'pin': pinController.text,
                      });
                    },
                    icon: Icon(account == null
                        ? Icons.person_add_alt_1_rounded
                        : Icons.save_rounded),
                    label: Text(
                        account == null ? 'Create profile' : 'Save changes'),
                  ),
                  const SizedBox(height: DesignSpacing.xs),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    pinController.dispose();
    confirmController.dispose();
    return result;
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Bad state: ', '')),
        backgroundColor: DesignColors.error,
      ),
    );
  }
}

class _LocalStaffAccessCard extends StatelessWidget {
  const _LocalStaffAccessCard({
    required this.icon,
    required this.title,
    required this.message,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: DesignColors.peach,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: DesignColors.brandDark),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignType.display.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  message,
                  style: DesignType.body.copyWith(
                    color: DesignColors.textSecondary,
                  ),
                ),
                if (footnote != null) ...[
                  const SizedBox(height: DesignSpacing.sm),
                  Text(
                    footnote!,
                    style: DesignType.body.copyWith(
                      fontSize: 12,
                      color: DesignColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocalStaffCard extends StatelessWidget {
  const _EmptyLocalStaffCard({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.xl),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? DesignColors.darkSurfaceElevated
              : DesignColors.surface,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? DesignColors.darkBorder
                : DesignColors.surfaceBorder,
          ),
        ),
        child: Column(
          children: [
            const Icon(Icons.groups_2_outlined,
                size: 38, color: DesignColors.brand),
            const SizedBox(height: DesignSpacing.sm),
            Text(
              'No staff profiles yet',
              style: DesignType.display.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: DesignSpacing.xs),
            Text(
              'Create one profile for each person who uses this register.',
              textAlign: TextAlign.center,
              style:
                  DesignType.body.copyWith(color: DesignColors.textSecondary),
            ),
            const SizedBox(height: DesignSpacing.md),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add first staff member'),
            ),
          ],
        ),
      );
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.account,
    required this.saving,
    required this.onEdit,
    required this.onToggle,
  });

  final Map<String, dynamic> account;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final active = account['isActive'] != false;
    final role = account['role']?.toString() ?? 'Staff';
    final name = account['name']?.toString() ?? 'Unnamed staff';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : DesignColors.surface,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
          color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.md,
          vertical: DesignSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor:
              active ? DesignColors.peach : DesignColors.surfaceMuted,
          foregroundColor: DesignColors.brandDark,
          child: Text(
            name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          name,
          style: DesignType.body.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: DesignSpacing.xs,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RolePill(label: role),
              _RolePill(label: active ? 'Active' : 'Paused', muted: !active),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          enabled: !saving,
          tooltip: 'Staff actions',
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'toggle') onToggle();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit profile')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(active ? 'Pause access' : 'Enable access'),
            ),
          ],
        ),
        onTap: saving ? null : onEdit,
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, this.muted = false});
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: muted ? DesignColors.surfaceMuted : DesignColors.peach,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: DesignType.body.copyWith(
            fontSize: 11,
            color: muted ? DesignColors.textSecondary : DesignColors.brandDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _RoleGuideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        decoration: BoxDecoration(
          color: DesignColors.peach.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What each role can do',
              style: DesignType.body.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            for (final role in LocalStaffRoles.names) ...[
              if (role != LocalStaffRoles.names.first)
                const SizedBox(height: DesignSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: DesignColors.brandDark, size: 18),
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: Text(
                      '$role · ${LocalStaffRoles.descriptionFor(role)}',
                      style: DesignType.body,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}
