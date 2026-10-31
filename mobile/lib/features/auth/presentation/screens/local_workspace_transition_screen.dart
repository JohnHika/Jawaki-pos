import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/app_roles.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/providers/local_workspace_capabilities.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/auth_provider.dart';

/// Safe transition for an already-authenticated account whose cloud POS
/// service has been retired. It keeps the active tenant/branch scope and the
/// local database, then replaces remote credentials with a device PIN.
class LocalWorkspaceTransitionScreen extends ConsumerStatefulWidget {
  const LocalWorkspaceTransitionScreen({super.key});

  @override
  ConsumerState<LocalWorkspaceTransitionScreen> createState() =>
      _LocalWorkspaceTransitionScreenState();
}

class _LocalWorkspaceTransitionScreenState
    extends ConsumerState<LocalWorkspaceTransitionScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _acceptedLocalDataNotice = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _continueLocally() async {
    if (_busy) return;
    if (_pinController.text.length != 6) {
      setState(() => _error = 'Choose a six-digit PIN.');
      return;
    }
    if (_pinController.text != _confirmPinController.text) {
      setState(() => _error = 'The PINs do not match.');
      return;
    }
    if (!_acceptedLocalDataNotice) {
      setState(
          () => _error = 'Tick the box to confirm you have read the note.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = getIt<AuthService>();
      await auth.adoptCurrentWorkspaceLocally(
        ownerPin: _pinController.text,
        acceptedLocalDataNotice: _acceptedLocalDataNotice,
      );
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).refreshFromService();
      final user = auth.currentUser ?? const <String, dynamic>{};
      final permissions = RolePermissions(
        user['permissions'] as List<dynamic>?,
      );
      final layout = businessLayoutFromUser(user);
      context.go(LocalWorkspaceCapabilities.homePathFor(permissions, layout));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          StateError value => value.message.toString(),
          ArgumentError value => value.message.toString(),
          _ =>
            'Something went wrong. Nothing was changed — please try again.',
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = getIt<AuthService>();
    final user = auth.currentUser ?? const <String, dynamic>{};
    final tenant = user['tenant'] is Map
        ? Map<String, dynamic>.from(user['tenant'] as Map)
        : const <String, dynamic>{};
    final businessName =
        (tenant['name'] ?? user['tenantName'] ?? 'Your shop').toString();
    final branchName = (user['branchName'] ?? 'Active branch').toString();
    final permissions = RolePermissions(user['permissions'] as List<dynamic>?);
    final canAdopt = permissions.role == AppRole.admin ||
        user['role']?.toString().toLowerCase() == 'admin';

    return Scaffold(
      appBar: const BrandedAppBar(title: 'One last step'),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg,
                DesignSpacing.lg,
                DesignSpacing.lg,
                DesignSpacing.xxxl,
              ),
              children: [
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.xl),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF242B37), Color(0xFF171B22)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.circular(DesignSpacing.radiusXxl),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: DesignColors.accent.withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusLg),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: DesignColors.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                      Text(
                        'Counterbase now runs right here on your phone',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: DesignSpacing.sm),
                      Text(
                        'Choose a PIN for $businessName. From now on this phone opens your shop on its own — everything stays on this device and no account sign-in is needed.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: DesignColors.textSecondary,
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: DesignSpacing.lg),
                      _WorkspaceIdentityCard(
                        businessName: businessName,
                        branchName: branchName,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                const _TransitionFact(
                  icon: Icons.inventory_2_rounded,
                  title: 'Everything you have is still here',
                  detail:
                      'Your products, customers, and the sales recorded on this device are untouched and stay exactly where they are.',
                ),
                const SizedBox(height: DesignSpacing.sm),
                const _TransitionFact(
                  icon: Icons.wifi_off_rounded,
                  title: 'Works fully offline',
                  detail:
                      'Sales, stock, and records keep working with no internet. This device keeps its own records and no longer shares them with other devices.',
                ),
                if (canAdopt) ...[
                  const SizedBox(height: DesignSpacing.xl),
                  _PinField(
                    controller: _pinController,
                    label: 'New six-digit PIN',
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  _PinField(
                    controller: _confirmPinController,
                    label: 'Confirm your PIN',
                  ),
                  const SizedBox(height: DesignSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: context.themed(DesignColors.surface),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusLg),
                      border: Border.all(
                        color: context.themed(DesignColors.surfaceBorder),
                      ),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: CheckboxListTile(
                        value: _acceptedLocalDataNotice,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _acceptedLocalDataNotice = value ?? false;
                                  _error = null;
                                }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text(
                          'I understand my records now live on this phone. They stay safe here, and I can back them up anytime from Settings → Backup.',
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: DesignSpacing.md),
                    Text(
                      _error!,
                      style: const TextStyle(color: DesignColors.error),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.lg),
                  FilledButton.icon(
                    onPressed: _busy ? null : _continueLocally,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_open_rounded),
                    label: Text(
                      _busy ? 'Setting up your shop…' : 'Start using my shop',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: DesignSpacing.xl),
                  const _TransitionFact(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'The shop owner does this step',
                    detail:
                        'This device needs the shop owner to choose the opening PIN. Please ask them to open Counterbase here once and set it.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceIdentityCard extends StatelessWidget {
  const _WorkspaceIdentityCard({
    required this.businessName,
    required this.branchName,
  });

  final String businessName;
  final String branchName;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront_rounded, color: DesignColors.accent),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(businessName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    branchName,
                    style: const TextStyle(color: DesignColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle_rounded,
                color: DesignColors.success, size: 20),
          ],
        ),
      );
}

class _TransitionFact extends StatelessWidget {
  const _TransitionFact({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(DesignSpacing.md),
        decoration: BoxDecoration(
          color: context.themed(DesignColors.surface),
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: context.themed(DesignColors.surfaceBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: DesignColors.accent),
            const SizedBox(width: DesignSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: DesignColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PinField extends StatelessWidget {
  const _PinField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        autofillHints: const [],
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.password_rounded),
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          ),
        ),
      );
}
