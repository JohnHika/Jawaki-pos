import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/services/receipt_printer_service.dart';
import '../../../../core/services/print_queue_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Settings keys for SharedPreferences. Printer keys delegate to
// PrinterSettingsKeys (receipt_printer_service.dart) so this screen and
// receipt_screen.dart's print action always agree on where those live.
class _SettingsKeys {
  static const autoPrintReceipt = PrinterSettingsKeys.autoPrint;
  static const printerName = PrinterSettingsKeys.printerName;
  static const printerMacAddress = PrinterSettingsKeys.printerMacAddress;
  static const paperWidth = PrinterSettingsKeys.paperWidth;
  static const notifySales = 'setting_notify_sales';
  static const notifyInventory = 'setting_notify_inventory';
  static const notifySync = 'setting_notify_sync';
}

String _initialFor(dynamic nameOrEmail) {
  final text = nameOrEmail?.toString().trim() ?? '';
  return text.isEmpty ? '?' : text[0].toUpperCase();
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final perms = ref.watch(permissionsProvider);
    final syncService = getIt<SyncService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    final hasPreferencesSection =
        perms.canConfigureSync || perms.canConfigurePrinter ||
            perms.canConfigureNotifications || perms.canSeeAppearance;

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Settings', showBackButton: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Profile header ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: DesignColors.accent.withValues(alpha: isDark ? 0.1 : 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: DesignColors.accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: DesignColors.accent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: DesignColors.accent.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initialFor(user?['name'] ?? user?['email']),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?['name'] ?? user?['email'] ?? 'User',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?['email'] ?? '',
                        style: TextStyle(color: secondaryColor, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? DesignColors.darkBg : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: DesignColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          (user?['role'] ?? 'CASHIER').toString().toUpperCase(),
                          style: const TextStyle(
                            color: DesignColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Preferences ──
          if (hasPreferencesSection) ...[
            const SettingsGroupLabel('Preferences'),
            GroupedCard(children: [
              if (perms.canConfigureSync)
                FutureBuilder(
                  future: syncService.getStats(),
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    return SettingsRow(
                      icon: Icons.sync_rounded,
                      title: 'Sync Status',
                      subtitle: stats?.hasPendingSync == true
                          ? '${stats?.pendingEvents ?? 0} pending events'
                          : 'All synced',
                      trailing: stats?.isOnline == true
                          ? const _StatusBadge(
                              text: 'Online', color: DesignColors.success)
                          : const _StatusBadge(
                              text: 'Offline', color: DesignColors.warning),
                      onTap: () => _showSyncSettings(context, syncService),
                    );
                  },
                ),
              if (perms.canConfigurePrinter)
                SettingsRow(
                  icon: Icons.print_rounded,
                  title: 'Printer Settings',
                  subtitle: 'Configure receipt printer',
                  onTap: () => _showPrinterSettings(context),
                ),
              if (perms.canConfigureNotifications)
                SettingsRow(
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  subtitle: 'Manage notification preferences',
                  onTap: () => _showNotificationSettings(context),
                ),
              if (perms.canSeeAppearance)
                SettingsRow(
                  icon: Icons.dark_mode_rounded,
                  title: 'Appearance',
                  subtitle: 'Light / Dark mode',
                  onTap: () => _showAppearanceSettings(context),
                ),
            ]),
          ],

          // ── Account ──
          const SettingsGroupLabel('Account'),
          GroupedCard(children: [
            SettingsRow(
              icon: Icons.lock_rounded,
              title: 'Change PIN',
              subtitle: 'Update your quick login PIN',
              onTap: () => _showChangePinDialog(context),
            ),
            SettingsRow(
              icon: Icons.wifi_off_rounded,
              title: 'Offline Access PIN',
              subtitle: 'Set a PIN to log in when a phone is acting as the server without internet',
              onTap: () => _showOfflineAccessPinDialog(context),
            ),
            SettingsRow(
              icon: Icons.security_rounded,
              title: 'Security',
              subtitle: 'Biometrics & auto-lock',
              onTap: () => _showSecuritySettings(context),
            ),
          ]),

          // ── Support ──
          const SettingsGroupLabel('Support'),
          GroupedCard(children: [
            SettingsRow(
              icon: Icons.help_rounded,
              title: 'Help & Support',
              subtitle: 'Get help with the app',
              onTap: () => _showHelpSupport(context),
            ),
            SettingsRow(
              icon: Icons.system_update_rounded,
              title: 'Check for Updates',
              subtitle: 'See if a newer version is available',
              onTap: () => _checkForUpdates(context),
            ),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '1.0.3';
                return SettingsRow(
                  icon: Icons.info_rounded,
                  title: 'About',
                  subtitle: 'Version $version',
                  onTap: () => _showAboutInfo(context),
                );
              },
            ),
          ]),

          // ── Administration (admin-only) ──
          if (perms.canManageUsers) ...[
            const SettingsGroupLabel('Administration'),
            GroupedCard(children: [
              SettingsRow(
                icon: Icons.people_rounded,
                title: 'User Management',
                subtitle: 'Manage staff, roles & permissions',
                onTap: () => context.push('/users'),
              ),
              SettingsRow(
                icon: Icons.store_rounded,
                title: 'Branch Management',
                subtitle: 'Manage store locations',
                onTap: () => _showBranchManagement(context),
              ),
              SettingsRow(
                icon: Icons.percent_rounded,
                title: 'Tax Rate',
                subtitle: getIt<AuthService>().taxRatePercent > 0
                    ? '${getIt<AuthService>().taxRatePercent.toStringAsFixed(getIt<AuthService>().taxRatePercent % 1 == 0 ? 0 : 1)}% applied to every sale'
                    : 'No tax applied to sales',
                onTap: () => _showTaxRateDialog(context, ref),
              ),
              SettingsRow(
                icon: Icons.image_rounded,
                title: 'Company Logo',
                subtitle: 'Update your logo, or trace it into a crisp SVG',
                onTap: () => _showLogoDialog(context, ref),
              ),
              SettingsRow(
                icon: Icons.schedule_rounded,
                title: 'Operating Hours',
                subtitle: 'Set open & close times per day',
                onTap: () => context.push('/settings/operating-hours'),
              ),
              if (perms.canExportData)
                SettingsRow(
                  icon: Icons.download_rounded,
                  title: 'Data Export',
                  subtitle: 'Export sales & reports',
                  onTap: () => _showDataExport(context, ref),
                ),
              if (perms.canSeeAuditTrail)
                SettingsRow(
                  icon: Icons.history_rounded,
                  title: 'Audit Trail',
                  subtitle: 'View system activity log',
                  onTap: () => _showAuditTrail(context),
                ),
            ]),
          ],

          const SizedBox(height: 8),

          // ── Logout ──
          GroupedCard(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Logout',
                isDestructive: true,
                onTap: () => _showLogoutDialog(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Axon POS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: border,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) async {
    // Capture the settings screen context BEFORE the async gap, since the
    // dialog's own context is disposed as soon as it closes.
    final settingsContext = context;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Logout',
      message:
          'Are you sure you want to logout? Any unsynced data will be saved locally.',
      confirmLabel: 'Logout',
      confirmColor: DesignColors.error,
    );
    if (!confirmed) return;

    await ref.read(authControllerProvider.notifier).logout();
    if (settingsContext.mounted) {
      settingsContext.go('/login');
    }
  }

  // ===== SYNC SETTINGS =====
  void _showSyncSettings(BuildContext context, SyncService syncService) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SettingsSheetScaffold(
        title: 'Sync Settings',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder(
              future: syncService.getStats(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                final storage = getIt<StorageService>();
                final lastSync = storage.getLastSyncAt();
                return GroupedCard(
                  margin: EdgeInsets.zero,
                  children: [
                    _InfoRow('Status',
                        stats?.isOnline == true ? 'Online' : 'Offline'),
                    _InfoRow('Pending Events', '${stats?.pendingEvents ?? 0}'),
                    if ((stats?.failedEvents ?? 0) > 0)
                      _InfoRow('Failed Events', '${stats?.failedEvents}',
                          valueColor: DesignColors.error),
                    _InfoRow('Last Sync',
                        lastSync != null ? _formatDateTime(lastSync) : 'Never'),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SettingsPrimaryButton(
                label: 'Sync Now',
                onPressed: () {
                  syncService.syncPendingEvents();
                  Navigator.pop(context);
                  showGlassSnackBar(context, 'Syncing...',
                      icon: Icons.sync_rounded, color: DesignColors.info);
                },
              ),
            ),
            FutureBuilder(
              future: syncService.getStats(),
              builder: (context, snapshot) {
                if ((snapshot.data?.failedEvents ?? 0) == 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: SettingsPrimaryButton(
                      label: 'Retry Failed Items',
                      onPressed: () {
                        syncService.retryFailedItems();
                        Navigator.pop(context);
                        showGlassSnackBar(context, 'Retrying failed items...',
                            icon: Icons.refresh_rounded,
                            color: DesignColors.warning);
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== PRINTER SETTINGS =====
  void _showPrinterSettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final autoPrint = prefs.getBool(_SettingsKeys.autoPrintReceipt) ?? false;
    final printerName = prefs.getString(_SettingsKeys.printerName) ?? '';
    final printerMacAddress =
        prefs.getString(_SettingsKeys.printerMacAddress) ?? '';
    final paperWidth = prefs.getString(_SettingsKeys.paperWidth) ?? '58mm';

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _PrinterSettingsSheet(
        autoPrint: autoPrint,
        printerName: printerName,
        printerMacAddress: printerMacAddress,
        paperWidth: paperWidth,
      ),
    );
  }

  // ===== NOTIFICATION SETTINGS =====
  void _showNotificationSettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final notifySales = prefs.getBool(_SettingsKeys.notifySales) ?? true;
    final notifyInventory =
        prefs.getBool(_SettingsKeys.notifyInventory) ?? true;
    final notifySync = prefs.getBool(_SettingsKeys.notifySync) ?? true;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _NotificationSettingsSheet(
        notifySales: notifySales,
        notifyInventory: notifyInventory,
        notifySync: notifySync,
      ),
    );
  }

  // ===== APPEARANCE SETTINGS =====
  void _showAppearanceSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final currentMode = ref.watch(themeModeProvider);
        return SettingsSheetScaffold(
          title: 'Appearance',
          child: GroupedCard(
            margin: EdgeInsets.zero,
            children: [
              SettingsRow(
                icon: Icons.light_mode_rounded,
                iconColor: currentMode == ThemeMode.light
                    ? DesignColors.accent
                    : null,
                title: 'Light Mode',
                trailing: currentMode == ThemeMode.light
                    ? const Icon(Icons.check_circle_rounded,
                        color: DesignColors.accent)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.light);
                  Navigator.pop(ctx);
                },
              ),
              SettingsRow(
                icon: Icons.dark_mode_rounded,
                iconColor: currentMode == ThemeMode.dark
                    ? DesignColors.accent
                    : null,
                title: 'Dark Mode',
                trailing: currentMode == ThemeMode.dark
                    ? const Icon(Icons.check_circle_rounded,
                        color: DesignColors.accent)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.dark);
                  Navigator.pop(ctx);
                },
              ),
              SettingsRow(
                icon: Icons.phone_android_rounded,
                iconColor: currentMode == ThemeMode.system
                    ? DesignColors.accent
                    : null,
                title: 'System Default',
                subtitle: 'Follow device theme',
                trailing: currentMode == ThemeMode.system
                    ? const Icon(Icons.check_circle_rounded,
                        color: DesignColors.accent)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.system);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      }),
    );
  }

  // ===== CHANGE PIN =====
  void _showChangePinDialog(BuildContext context) async {
    final storage = getIt<StorageService>();
    final hasExistingPin = await storage.hasLocalPinSet();
    if (!context.mounted) return;

    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return SettingsDialog(
            title: hasExistingPin ? 'Change PIN' : 'Set Quick-Unlock PIN',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasExistingPin) ...[
                  TextField(
                    controller: currentPinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current PIN',
                      hintText: '****',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This PIN unlocks the app quickly without needing a '
                      'network connection.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ),
                TextField(
                  controller: newPinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New PIN',
                    hintText: '****',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New PIN',
                    hintText: '****',
                    counterText: '',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: DesignColors.error, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              SettingsPrimaryButton(
                label: 'Change PIN',
                onPressed: () async {
                  final newPin = newPinController.text;
                  final confirmPin = confirmPinController.text;

                  if (hasExistingPin) {
                    final currentPin = currentPinController.text;
                    if (currentPin.length != 4) {
                      setDialogState(
                          () => error = 'Enter your current 4-digit PIN');
                      return;
                    }
                    final isCorrect = await storage.verifyLocalPin(currentPin);
                    if (!isCorrect) {
                      setDialogState(() => error = 'Current PIN is incorrect');
                      return;
                    }
                  }
                  if (newPin.length != 4) {
                    setDialogState(() => error = 'New PIN must be 4 digits');
                    return;
                  }
                  if (newPin != confirmPin) {
                    setDialogState(() => error = 'PINs do not match');
                    return;
                  }

                  await storage.setLocalPin(newPin);

                  // Also push the PIN to the server so it works via the
                  // network fallback on a device that has never stored a
                  // local PIN hash (e.g. a fresh install, or a different
                  // device for the same account) — without this, only the
                  // device where the PIN was set could ever unlock with it.
                  var serverSyncFailed = false;
                  try {
                    await getIt<ApiClient>().setPin(newPin);
                  } catch (_) {
                    serverSyncFailed = true;
                  }

                  if (!context.mounted || !dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _showSnack(
                    context,
                    serverSyncFailed
                        ? 'PIN changed on this device. Reconnect to sync it to your account.'
                        : 'PIN changed successfully',
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== OFFLINE ACCESS PIN =====
  // Authorizes this account to log into ANY phone acting as a local
  // server (Settings → Backend Server) with no internet connection.
  // Distinct from _showChangePinDialog's quick-unlock PIN, which only
  // unlocks an already-authenticated session on this specific device.
  void _showOfflineAccessPinDialog(BuildContext context) {
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return SettingsDialog(
            title: 'Offline Access PIN',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Set a PIN so you can log in as yourself on a phone '
                    'that\'s acting as the local server, even with no '
                    'internet connection. Must be set now, while online.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Offline Access PIN',
                    hintText: '4-6 digits',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPinController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                    hintText: '4-6 digits',
                    counterText: '',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: DesignColors.error, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              SettingsPrimaryButton(
                label: 'Save',
                isLoading: isSaving,
                onPressed: () async {
                  final pin = pinController.text;
                  final confirmPin = confirmPinController.text;

                  if (pin.length < 4 || pin.length > 6) {
                    setDialogState(() => error = 'PIN must be 4-6 digits');
                    return;
                  }
                  if (pin != confirmPin) {
                    setDialogState(() => error = 'PINs do not match');
                    return;
                  }

                  setDialogState(() {
                    isSaving = true;
                    error = null;
                  });

                  try {
                    await getIt<ApiClient>().setOfflineAccessPin(pin);
                    if (!context.mounted || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    _showSnack(context, 'Offline access PIN set successfully');
                  } catch (e) {
                    setDialogState(() {
                      isSaving = false;
                      error = 'Could not save. Check your connection and try again.';
                    });
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== SECURITY SETTINGS =====
  void _showSecuritySettings(BuildContext context) async {
    final storage = getIt<StorageService>();
    final biometricEnabled = storage.isBiometricEnabled();
    final requireUnlockOnResume = storage.requireUnlockOnResume();
    final autoLockMinutes = storage.getAutoLockMinutes();
    final authService = getIt<AuthService>();
    final biometricAvailable =
        await authService.isDeviceAuthenticationAvailable();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 1.0,
        minChildSize: 0.45,
        builder: (_, scrollController) => _SecuritySettingsSheet(
          biometricEnabled: biometricEnabled,
          biometricAvailable: biometricAvailable,
          requireUnlockOnResume: requireUnlockOnResume,
          autoLockMinutes: autoLockMinutes,
          scrollController: scrollController,
        ),
      ),
    );
  }

  // ===== HELP & SUPPORT =====
  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SettingsSheetScaffold(
          title: 'Help & Support',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsGroupLabel('Contact'),
              GroupedCard(
                children: [
                  const SettingsRow(
                    icon: Icons.email_outlined,
                    title: 'Email Support',
                    subtitle: 'johnkimani576@gmail.com',
                  ),
                  SettingsRow(
                    icon: Icons.phone_outlined,
                    title: 'Phone Support',
                    subtitle: '0742126582',
                    onTap: () {},
                  ),
                ],
              ),
              const SettingsGroupLabel('Resources'),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.quiz_outlined,
                    title: 'FAQ',
                    subtitle: 'Frequently asked questions',
                    onTap: () {
                      Navigator.pop(context);
                      _showFAQ(context);
                    },
                  ),
                  SettingsRow(
                    icon: Icons.description_outlined,
                    title: 'User Guide',
                    subtitle: 'How to use the POS system',
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/user-guide');
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFAQ(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        title: 'FAQ',
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Q: How do I add items to the cart?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                  'A: Tap a product on the POS screen and select the quantity.'),
              SizedBox(height: 16),
              Text('Q: How do I manage products?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                  'A: Go to the Products tab. Use the + button to add products and the categories button to manage categories.'),
              SizedBox(height: 16),
              Text('Q: Can I work offline?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                  'A: Yes! Sales and product data are stored locally. They will sync automatically when you\'re back online.'),
              SizedBox(height: 16),
              Text('Q: How do I change my PIN?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('A: Go to Settings > Change PIN.'),
              SizedBox(height: 16),
              Text('Q: How do I process a refund?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text(
                  'A: Refund functionality will be available in a future update.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }

  // ===== ABOUT =====
  void _showAboutInfo(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final titleColor =
            isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
        final secondaryColor = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        final border =
            isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
        final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
        // Deliberately a plain Dialog, not Flutter's AboutDialog — that
        // widget always injects a "VIEW LICENSES" button surfacing every
        // open-source package's license text, which is developer-facing
        // noise a customer has no use for and no way to hide.
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: DesignColors.brand,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storefront, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 16),
                Text('Axon POS',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800, color: titleColor)),
                const SizedBox(height: 4),
                Text(_formatReleaseName(info.version),
                    style: TextStyle(fontSize: 13, color: secondaryColor)),
                const SizedBox(height: 16),
                Text(
                  'A complete point-of-sale system for managing sales, inventory, and business operations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: titleColor, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Powered by Arche Axon Intelligence',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: secondaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => launchUrl(
                          Uri.parse('https://arche-axon.xyz'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(
                          'arche-axon.xyz',
                          style: TextStyle(
                              color: DesignColors.brand,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('© 2026 Arche Axon Intelligence',
                    style: TextStyle(color: secondaryColor, fontSize: 11)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(BuildContext context, String message,
      {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? DesignColors.error : null,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatReleaseName(String version) {
    final parts = version.split('.');
    if (parts.length >= 2) {
      final marketingVersion = parts.length >= 3 && parts[2] != '0'
          ? parts.take(3).join('.')
          : parts.take(2).join('.');
      return 'Axon POS $marketingVersion';
    }

    return 'Axon POS $version';
  }

  // ===== ADMIN-ONLY: BRANCH MANAGEMENT =====
  // ===== ADMIN-ONLY: TAX RATE =====
  void _showTaxRateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: getIt<AuthService>().taxRatePercent > 0
          ? getIt<AuthService>().taxRatePercent.toString()
          : '',
    );
    bool isSaving = false;
    bool showOnReceipt = getIt<AuthService>().showTaxOnReceipt;
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          return SettingsDialog(
          title: 'Tax Rate',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set the VAT/sales tax percentage applied to every sale. Leave at 0 to charge no tax.',
                style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Tax percentage',
                  suffixText: '%',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.receipt_rounded,
                    title: 'Show tax on receipt',
                    subtitle:
                        'Print the tax amount as its own line on printed receipts',
                    trailing: Switch(
                      value: showOnReceipt,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (value) =>
                          setDialogState(() => showOnReceipt = value),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            SettingsPrimaryButton(
              label: 'Save',
              isLoading: isSaving,
              onPressed: () async {
                final text = controller.text.trim();
                final rate = text.isEmpty ? 0.0 : double.tryParse(text);
                if (rate == null || rate < 0 || rate > 100) {
                  setDialogState(
                      () => error = 'Enter a number between 0 and 100');
                  return;
                }
                setDialogState(() {
                  isSaving = true;
                  error = null;
                });
                try {
                  final apiClient = getIt<ApiClient>();
                  final authService = getIt<AuthService>();
                  final updated = await apiClient.updateCurrentTenant(
                    taxRatePercent: rate,
                    showTaxOnReceipt: showOnReceipt,
                  );
                  await authService.updateTenantSession({
                    'id': updated['id'],
                    'name': updated['name'],
                    'settings': updated['settings'],
                  });
                  ref.read(authControllerProvider.notifier).refreshFromService();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  if (context.mounted) {
                    showGlassSnackBar(
                      context,
                      rate > 0
                          ? 'Tax rate set to ${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%'
                          : 'Tax removed — sales will not be taxed',
                      icon: Icons.check_circle_rounded,
                      color: DesignColors.success,
                    );
                  }
                } catch (e) {
                  setDialogState(() {
                    isSaving = false;
                    error = 'Could not save. Check your connection.';
                  });
                }
              },
            ),
          ],
          );
        },
      ),
    );
  }

  /// Update the tenant's logo, optionally tracing it into a scalable SVG
  /// (deterministic vectorization via the backend, no AI involved). Mirrors
  /// the picker used at first-time company setup, but reachable any time so
  /// existing shops can swap or vectorize their logo later.
  void _showLogoDialog(BuildContext context, WidgetRef ref) {
    File? logoFile;
    bool vectorize = false;
    bool isSaving = false;
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
          final secondary = isDark
              ? DesignColors.darkTextSecondary
              : DesignColors.textSecondary;

          Future<void> pickLogo() async {
            final picker = ImagePicker();
            final image = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 512,
              maxHeight: 512,
              imageQuality: 85,
            );
            if (image == null) return;
            setDialogState(() {
              logoFile = File(image.path);
              error = null;
            });
          }

          return SettingsDialog(
            title: 'Company Logo',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a new logo image, or trace your existing one into a crisp scalable SVG.',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: isSaving ? null : pickLogo,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? DesignColors.darkBorder
                            : DesignColors.surfaceBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: isDark
                                ? DesignColors.darkBorder
                                : DesignColors.surfaceBorder,
                            shape: BoxShape.circle,
                          ),
                          child: logoFile != null
                              ? ClipOval(
                                  child: Image.file(logoFile!, fit: BoxFit.cover),
                                )
                              : Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 24,
                                  color: secondary,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            logoFile != null ? 'New logo selected' : 'Choose an image',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? DesignColors.darkTextPrimary
                                  : DesignColors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: secondary),
                      ],
                    ),
                  ),
                ),
                if (logoFile != null) ...[
                  const SizedBox(height: 14),
                  GroupedCard(
                    margin: EdgeInsets.zero,
                    children: [
                      SettingsRow(
                        icon: Icons.auto_fix_high_rounded,
                        title: 'Make it a crisp SVG logo',
                        subtitle:
                            'Traces your image into a scalable vector — stays sharp at any size. Best for clean, simple logos.',
                        trailing: Switch(
                          value: vectorize,
                          activeThumbColor: DesignColors.accent,
                          onChanged: (v) => setDialogState(() => vectorize = v),
                        ),
                      ),
                    ],
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: DesignColors.error, fontSize: 12)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              SettingsPrimaryButton(
                label: 'Save',
                isLoading: isSaving,
                onPressed: logoFile == null
                    ? null
                    : () async {
                        setDialogState(() {
                          isSaving = true;
                          error = null;
                        });
                        try {
                          final apiClient = getIt<ApiClient>();
                          final authService = getIt<AuthService>();
                          final fileName = logoFile!.uri.pathSegments.isNotEmpty
                              ? logoFile!.uri.pathSegments.last
                              : 'company-logo.jpg';

                          String? logoUrl;
                          String? logoPublicId;
                          if (vectorize) {
                            final v = await apiClient.vectorizeLogo(
                              filePath: logoFile!.path,
                              fileName: fileName,
                            );
                            logoUrl = (v['svgUrl'] ?? v['rasterUrl']) as String?;
                            logoPublicId = v['publicId'] as String?;
                          } else {
                            final uploadResult = await apiClient.uploadImage(
                              filePath: logoFile!.path,
                              fileName: fileName,
                              type: 'logo',
                            );
                            logoUrl = uploadResult['url'] as String?;
                            logoPublicId = uploadResult['publicId'] as String?;
                          }

                          final updated = await apiClient.updateCurrentTenant(
                            logo: logoUrl,
                            logoPublicId: logoPublicId,
                          );
                          await authService.updateTenantSession({
                            'id': updated['id'],
                            'name': updated['name'],
                            'logo': updated['logo'],
                            'logoPublicId': updated['logoPublicId'],
                            'settings': updated['settings'],
                          });
                          ref.read(authControllerProvider.notifier).refreshFromService();

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            showGlassSnackBar(
                              context,
                              vectorize
                                  ? 'Logo updated with a crisp SVG version'
                                  : 'Logo updated',
                              icon: Icons.check_circle_rounded,
                              color: DesignColors.success,
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSaving = false;
                            error = 'Could not save. Check your connection.';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBranchManagement(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) =>
            _BranchManagementSheet(scrollController: scrollController),
      ),
    );
  }

  // ===== ADMIN-ONLY: DATA EXPORT =====
  void _showDataExport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SettingsSheetScaffold(
        title: 'Data Export',
        child: GroupedCard(
          margin: EdgeInsets.zero,
          children: [
            SettingsRow(
              icon: Icons.receipt_long_rounded,
              title: 'Export Sales Data',
              subtitle: 'PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportSalesData(context, ref);
              },
            ),
            SettingsRow(
              icon: Icons.inventory_rounded,
              title: 'Export Inventory',
              subtitle: 'PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportInventory(context, ref);
              },
            ),
            SettingsRow(
              icon: Icons.category_rounded,
              title: 'Export Products',
              subtitle: 'PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportProducts(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSalesData(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Export Sales Data',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Generating sales export...');
      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      final sales = await db.getSalesByDateRange(
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month, now.day, 23, 59, 59),
      );

      const headers = [
        'Receipt Number',
        'Date',
        'Subtotal',
        'Discount',
        'Tax',
        'Total',
        'Payment Method',
        'Cashier ID',
        'Branch ID',
        'Status',
      ];
      final rows = [
        for (final s in sales)
          [
            s.receiptNumber,
            s.createdAt.toIso8601String(),
            '${s.subtotal}',
            '${s.discount}',
            '${s.tax}',
            '${s.total}',
            s.paymentMethod,
            s.cashierId,
            s.branchId,
            s.status,
          ],
      ];

      if (!context.mounted) return;
      if (format == ShareFormat.csv) {
        final csv = ExportDocumentService.buildCsv(headers, rows);
        await ExportDocumentService.shareCsv(csv, 'sales_export');
      } else {
        final identity = ref.read(tenantIdentityProvider);
        final logoBytes =
            await ExportDocumentService.fetchLogoBytes(identity.logoUrl);
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Sales Export',
          companyName: identity.companyName,
          subtitle: 'Month to date — ${sales.length} records',
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(heading: 'Sales', headers: headers, rows: rows),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'sales_export');
      }
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  Future<void> _exportInventory(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Export Inventory',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Generating inventory export...');
      final db = getIt<AppDatabase>();
      final data = await db.getInventoryReport();

      const headers = [
        'Product ID',
        'Name',
        'SKU',
        'Category',
        'Price',
        'Cost Price',
        'Stock',
        'Min Stock',
      ];
      final rows = [
        for (final d in data)
          [
            d['id'] as String,
            d['name'] as String,
            d['sku'] as String,
            d['categoryName'] as String,
            '${d['price']}',
            '${d['costPrice']}',
            '${d['stock']}',
            '${d['minStock']}',
          ],
      ];

      if (!context.mounted) return;
      if (format == ShareFormat.csv) {
        final csv = ExportDocumentService.buildCsv(headers, rows);
        await ExportDocumentService.shareCsv(csv, 'inventory_export');
      } else {
        final identity = ref.read(tenantIdentityProvider);
        final logoBytes =
            await ExportDocumentService.fetchLogoBytes(identity.logoUrl);
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Inventory Export',
          companyName: identity.companyName,
          subtitle: '${data.length} items',
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(
                heading: 'Inventory', headers: headers, rows: rows),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'inventory_export');
      }
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  Future<void> _exportProducts(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Export Products',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Generating products export...');
      final db = getIt<AppDatabase>();
      final products = await db.getAllProducts();

      const headers = [
        'ID',
        'SKU',
        'Name',
        'Category ID',
        'Price',
        'Cost Price',
        'Unit',
        'Active',
      ];
      final rows = [
        for (final p in products)
          [
            p.id,
            p.sku,
            p.name,
            p.categoryId,
            '${p.price}',
            '${p.costPrice ?? 0}',
            p.unit,
            '${p.isActive}',
          ],
      ];

      if (!context.mounted) return;
      if (format == ShareFormat.csv) {
        final csv = ExportDocumentService.buildCsv(headers, rows);
        await ExportDocumentService.shareCsv(csv, 'products_export');
      } else {
        final identity = ref.read(tenantIdentityProvider);
        final logoBytes =
            await ExportDocumentService.fetchLogoBytes(identity.logoUrl);
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Products Export',
          companyName: identity.companyName,
          subtitle: '${products.length} products',
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(
                heading: 'Products', headers: headers, rows: rows),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'products_export');
      }
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  // ===== ADMIN-ONLY: AUDIT TRAIL =====
  void _showAuditTrail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final border =
              isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
          final secondaryColor = isDark
              ? DesignColors.darkTextSecondary
              : DesignColors.textSecondary;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: border,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 18),
                Text('Audit Trail',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Recent system activity',
                    style: TextStyle(color: secondaryColor)),
                const SizedBox(height: 18),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: getIt<ApiClient>().getAuditLog(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Couldn\'t load audit trail',
                          subtitle: 'Check your connection and try again.',
                          iconColor: DesignColors.error,
                        );
                      }
                      final items = (snapshot.data?['items'] as List? ?? [])
                          .cast<Map<String, dynamic>>();
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.history_rounded,
                          title: 'No activity yet',
                          subtitle: 'Actions like logins and branch changes will appear here.',
                        );
                      }
                      return ListView(
                        controller: scrollController,
                        children: [
                          GroupedCard(
                            margin: EdgeInsets.zero,
                            children: items
                                .map((entry) => _AuditEntry(
                                      icon: _auditIconFor(
                                          entry['action'] as String? ?? '',
                                          entry['entityType'] as String? ?? ''),
                                      title: _auditTitleFor(
                                          entry['action'] as String? ?? '',
                                          entry['entityType'] as String? ?? ''),
                                      subtitle: entry['userName'] as String? ??
                                          'System',
                                      time: entry['createdAt'] != null
                                          ? _formatDateTime(DateTime.parse(
                                              entry['createdAt'] as String))
                                          : '',
                                    ))
                                .toList(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _auditIconFor(String action, String entityType) {
    if (entityType == 'session') return Icons.login_rounded;
    if (entityType == 'pin') return Icons.lock_rounded;
    if (entityType == 'branch') return Icons.store_rounded;
    if (action == 'DELETE') return Icons.delete_outline_rounded;
    return Icons.history_rounded;
  }

  String _auditTitleFor(String action, String entityType) {
    if (entityType == 'session') return 'Logged in';
    if (entityType == 'pin') return 'PIN changed';
    if (entityType == 'branch') {
      switch (action) {
        case 'CREATE':
          return 'Branch created';
        case 'UPDATE':
          return 'Branch updated';
        case 'DELETE':
          return 'Branch deleted';
      }
    }
    return '$action $entityType'.trim();
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ===== UPDATE CHECK =====
  Future<void> _checkForUpdates(BuildContext context) async {
    // Capture navigator & messenger BEFORE any await so they remain valid
    // even if this widget is unmounted while the network call is in-flight.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final updateService = getIt<UpdateCheckService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (ctx) => const AlertDialog(
        title: Text('Checking for Updates'),
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Checking the latest release...'),
          ],
        ),
      ),
    );

    bool wasUpdateShown = false;
    try {
      wasUpdateShown = await updateService.checkForUpdates(force: true);
    } catch (_) {
      wasUpdateShown = false;
    } finally {
      // Always dismiss the loading dialog — even if context was unmounted or an
      // exception was thrown.  Using the captured NavigatorState is reliable
      // because it doesn't require context.mounted to be true.
      try {
        navigator.pop();
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (updateService.hasOptionalUpdateAvailable) {
      updateService.showCachedOptionalUpdateDialog(context);
    } else if (!wasUpdateShown) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You\'re on the latest version! ✅'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ===== PRINTER SETTINGS SHEET =====
class _PrinterSettingsSheet extends StatefulWidget {
  final bool autoPrint;
  final String printerName;
  final String printerMacAddress;
  final String paperWidth;

  const _PrinterSettingsSheet({
    required this.autoPrint,
    required this.printerName,
    required this.printerMacAddress,
    required this.paperWidth,
  });

  @override
  State<_PrinterSettingsSheet> createState() => _PrinterSettingsSheetState();
}

class _PrinterSettingsSheetState extends State<_PrinterSettingsSheet> {
  late bool _autoPrint;
  late String _paperWidth;
  late String _printerName;
  late String _printerMacAddress;
  bool _isScanning = false;
  bool _isConnecting = false;
  List<PairedPrinter> _pairedPrinters = [];

  // Whether THIS device is the one designated to hold the Bluetooth
  // connection when several devices share one printer — null while still
  // loading from the backend.
  bool? _isDesignatedPrinter;
  bool _isSavingDesignation = false;

  @override
  void initState() {
    super.initState();
    _autoPrint = widget.autoPrint;
    _paperWidth = widget.paperWidth;
    _printerName = widget.printerName;
    _printerMacAddress = widget.printerMacAddress;
    _loadDesignation();
  }

  Future<void> _loadDesignation() async {
    final designated = await getIt<PrintQueueService>().isDesignatedPrinter();
    if (mounted) setState(() => _isDesignatedPrinter = designated);
  }

  Future<void> _setDesignation(bool value) async {
    setState(() => _isSavingDesignation = true);
    try {
      await getIt<PrintQueueService>().setThisDeviceAsPrinter(value);
      if (mounted) setState(() => _isDesignatedPrinter = value);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not update printer device: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isSavingDesignation = false);
    }
  }

  Future<void> _scanForPrinters() async {
    setState(() => _isScanning = true);
    try {
      final printer = getIt<ReceiptPrinterService>();

      var hasPermission = await printer.hasPermission;
      if (!hasPermission) {
        hasPermission = await printer.requestPermission();
      }
      if (!hasPermission) {
        if (mounted) {
          showGlassSnackBar(
              context, 'Bluetooth permission is required to find printers',
              icon: Icons.bluetooth_disabled_rounded,
              color: DesignColors.warning);
        }
        return;
      }

      final enabled = await printer.isBluetoothEnabled;
      if (!enabled) {
        if (mounted) {
          showGlassSnackBar(context, 'Turn on Bluetooth to find printers',
              icon: Icons.bluetooth_disabled_rounded,
              color: DesignColors.warning);
        }
        return;
      }

      final paired = await printer.getPairedPrinters();
      setState(() => _pairedPrinters = paired);

      if (paired.isEmpty && mounted) {
        showGlassSnackBar(
            context,
            'No paired Bluetooth devices found — pair your printer in phone Bluetooth settings first',
            icon: Icons.bluetooth_searching_rounded,
            color: DesignColors.info);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Could not scan for printers: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connectTo(PairedPrinter device) async {
    setState(() => _isConnecting = true);
    try {
      final connected =
          await getIt<ReceiptPrinterService>().connect(device.macAddress);
      if (connected) {
        setState(() {
          _printerName = device.name;
          _printerMacAddress = device.macAddress;
        });
        if (mounted) {
          showGlassSnackBar(context, 'Connected to ${device.name}',
              icon: Icons.check_circle_rounded, color: DesignColors.success);
        }
      } else if (mounted) {
        showGlassSnackBar(context, 'Could not connect to ${device.name}',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Connection failed: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SettingsSheetScaffold(
        title: 'Printer Settings',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GroupedCard(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  icon: Icons.print_rounded,
                  title: _printerMacAddress.isEmpty
                      ? 'No printer connected'
                      : _printerName,
                  subtitle: _printerMacAddress.isEmpty
                      ? 'Scan and connect a Bluetooth printer'
                      : _printerMacAddress,
                  iconColor: _printerMacAddress.isEmpty
                      ? DesignColors.textTertiary
                      : DesignColors.success,
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _paperWidth,
              decoration: InputDecoration(
                labelText: 'Paper Width',
                prefixIcon: const Icon(Icons.straighten_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              items: const [
                DropdownMenuItem(value: '58mm', child: Text('58mm (Small)')),
                DropdownMenuItem(value: '80mm', child: Text('80mm (Standard)')),
              ],
              onChanged: (v) => setState(() => _paperWidth = v ?? '58mm'),
            ),
            const SizedBox(height: 14),
            GroupedCard(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  icon: Icons.receipt_long_rounded,
                  title: 'Auto-print receipts',
                  subtitle: 'Print receipt after each sale',
                  trailing: Switch(
                    value: _autoPrint,
                    activeThumbColor: DesignColors.accent,
                    onChanged: (v) => setState(() => _autoPrint = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const SettingsGroupLabel('SHARED PRINTER'),
            GroupedCard(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  icon: Icons.smartphone_rounded,
                  title: 'This device is the printer',
                  subtitle: _printerMacAddress.isEmpty
                      ? 'Connect a printer above first'
                      : 'Other staff devices will queue receipts here to print — '
                          'turn this on only on the phone physically connected '
                          'to the till printer.',
                  trailing: _isDesignatedPrinter == null || _isSavingDesignation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Switch(
                          value: _isDesignatedPrinter!,
                          activeThumbColor: DesignColors.accent,
                          onChanged: _printerMacAddress.isEmpty
                              ? null
                              : (v) => _setDesignation(v),
                        ),
                ),
              ],
            ),
            if (_pairedPrinters.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SettingsGroupLabel('PAIRED DEVICES'),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: _pairedPrinters
                    .map((device) => SettingsRow(
                          icon: Icons.bluetooth_rounded,
                          title: device.name,
                          subtitle: device.macAddress,
                          trailing: _isConnecting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : (device.macAddress == _printerMacAddress
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: DesignColors.success)
                                  : null),
                          onTap: _isConnecting ? null : () => _connectTo(device),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isScanning ? null : _scanForPrinters,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Scan Printers'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SettingsPrimaryButton(
                    label: 'Save',
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool(
                          _SettingsKeys.autoPrintReceipt, _autoPrint);
                      await prefs.setString(
                          _SettingsKeys.printerName, _printerName);
                      await prefs.setString(
                          _SettingsKeys.printerMacAddress, _printerMacAddress);
                      await prefs.setString(
                          _SettingsKeys.paperWidth, _paperWidth);
                      if (context.mounted) {
                        Navigator.pop(context);
                        showGlassSnackBar(context, 'Printer settings saved',
                            icon: Icons.check_circle_rounded,
                            color: DesignColors.success);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ===== NOTIFICATION SETTINGS SHEET =====
class _NotificationSettingsSheet extends StatefulWidget {
  final bool notifySales;
  final bool notifyInventory;
  final bool notifySync;

  const _NotificationSettingsSheet({
    required this.notifySales,
    required this.notifyInventory,
    required this.notifySync,
  });

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  late bool _notifySales;
  late bool _notifyInventory;
  late bool _notifySync;

  @override
  void initState() {
    super.initState();
    _notifySales = widget.notifySales;
    _notifyInventory = widget.notifyInventory;
    _notifySync = widget.notifySync;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        child: SettingsSheetScaffold(
          title: 'Notifications',
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Sales Alerts',
                    subtitle: 'Get notified for completed sales',
                    trailing: Switch(
                      value: _notifySales,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) => setState(() => _notifySales = v),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.inventory_rounded,
                    title: 'Inventory Alerts',
                    subtitle: 'Low stock and reorder reminders',
                    trailing: Switch(
                      value: _notifyInventory,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) => setState(() => _notifyInventory = v),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.sync_rounded,
                    title: 'Sync Alerts',
                    subtitle: 'Notify when sync completes or fails',
                    trailing: Switch(
                      value: _notifySync,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) => setState(() => _notifySync = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: SettingsPrimaryButton(
                  label: 'Save',
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(
                        _SettingsKeys.notifySales, _notifySales);
                    await prefs.setBool(
                        _SettingsKeys.notifyInventory, _notifyInventory);
                    await prefs.setBool(_SettingsKeys.notifySync, _notifySync);

                    // These three toggles are per-category filters; the OS
                    // notification permission itself is a single shared
                    // gate, so any category being on means this device
                    // needs to be registered to actually receive pushes.
                    final anyEnabled =
                        _notifySales || _notifyInventory || _notifySync;
                    String? permissionMessage;
                    if (anyEnabled) {
                      final granted = await getIt<NotificationService>()
                          .requestPermission();
                      if (!granted) {
                        permissionMessage =
                            'Notifications are blocked in your phone settings — enable them there to receive alerts.';
                      }
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(permissionMessage ??
                              'Notification settings saved'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== SECURITY SETTINGS SHEET =====
class _SecuritySettingsSheet extends StatefulWidget {
  final bool biometricEnabled;
  final bool biometricAvailable;
  final bool requireUnlockOnResume;
  final int autoLockMinutes;
  final ScrollController scrollController;

  const _SecuritySettingsSheet({
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.requireUnlockOnResume,
    required this.autoLockMinutes,
    required this.scrollController,
  });

  @override
  State<_SecuritySettingsSheet> createState() => _SecuritySettingsSheetState();
}

class _SecuritySettingsSheetState extends State<_SecuritySettingsSheet> {
  late bool _biometricEnabled;
  late bool _requireUnlockOnResume;
  late int _autoLockMinutes;
  bool _isConfirmingBiometric = false;

  @override
  void initState() {
    super.initState();
    _biometricEnabled = widget.biometricEnabled;
    _requireUnlockOnResume = widget.requireUnlockOnResume;
    _autoLockMinutes = widget.autoLockMinutes;
  }

  /// Turning biometric login on/off takes effect immediately (not deferred
  /// to the Save button) because enabling it requires proving — right
  /// then, with a real OS biometric prompt — that this device's
  /// fingerprint/face actually works. There's no way to "preview" that
  /// without invoking it, and deferring would let a user save a setting
  /// that was never actually verified.
  Future<void> _onBiometricToggled(bool enabling) async {
    if (!enabling) {
      setState(() => _biometricEnabled = false);
      await getIt<StorageService>().setBiometricEnabled(false);
      return;
    }

    setState(() => _isConfirmingBiometric = true);
    try {
      final confirmed = await getIt<AuthService>().confirmBiometricEnrollment();
      setState(() {
        _biometricEnabled = confirmed;
        _isConfirmingBiometric = false;
      });
      await getIt<StorageService>().setBiometricEnabled(confirmed);
      if (!confirmed && mounted) {
        showGlassSnackBar(context, 'Biometric check failed or was cancelled',
            icon: Icons.fingerprint_rounded, color: DesignColors.error);
      }
    } catch (e) {
      setState(() {
        _biometricEnabled = false;
        _isConfirmingBiometric = false;
      });
      if (mounted) {
        showGlassSnackBar(context, 'Could not verify biometrics: $e',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: border,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Text('Security',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            GroupedCard(
              children: [
                SettingsRow(
                  icon: Icons.security_rounded,
                  title: 'Biometric Login',
                  subtitle: widget.biometricAvailable
                      ? 'Use device fingerprint, face, PIN, or pattern to unlock'
                      : 'Not available on this device',
                  enabled: widget.biometricAvailable && !_isConfirmingBiometric,
                  trailing: _isConfirmingBiometric
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Switch(
                          value: _biometricEnabled && widget.biometricAvailable,
                          activeThumbColor: DesignColors.accent,
                          onChanged: widget.biometricAvailable
                              ? _onBiometricToggled
                              : null,
                        ),
                ),
                SettingsRow(
                  icon: Icons.lock_clock_rounded,
                  title: 'Require unlock when app reopens',
                  subtitle: 'Ask for authentication after leaving the app',
                  trailing: Switch(
                    value: _requireUnlockOnResume,
                    activeThumbColor: DesignColors.accent,
                    onChanged: (v) =>
                        setState(() => _requireUnlockOnResume = v),
                  ),
                ),
              ],
            ),
            GroupedCard(
              margin: EdgeInsets.zero,
              children: [
                SettingsRow(
                  icon: Icons.timer_outlined,
                  title: 'Auto-lock after',
                  enabled: _requireUnlockOnResume,
                  trailing: DropdownButton<int>(
                    value: _autoLockMinutes,
                    underline: const SizedBox(),
                    onChanged: _requireUnlockOnResume
                        ? (v) => setState(() => _autoLockMinutes = v ?? -1)
                        : null,
                    items: const [
                      DropdownMenuItem(value: -1, child: Text('Immediately')),
                      DropdownMenuItem(value: 1, child: Text('1 min')),
                      DropdownMenuItem(value: 5, child: Text('5 min')),
                      DropdownMenuItem(value: 15, child: Text('15 min')),
                      DropdownMenuItem(value: 30, child: Text('30 min')),
                      DropdownMenuItem(value: 0, child: Text('Never')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: SettingsPrimaryButton(
                label: 'Save',
                onPressed: () async {
                  // Biometric is committed immediately by the toggle itself
                  // (it needs a real, just-in-time authenticate() check) —
                  // only the remaining two settings are deferred to Save.
                  final storage = getIt<StorageService>();
                  await storage
                      .setRequireUnlockOnResume(_requireUnlockOnResume);
                  await storage.setAutoLockMinutes(_autoLockMinutes);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Security settings saved')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== SHARED WIDGETS =====
class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(label,
                style: TextStyle(color: secondaryColor, fontSize: 13.5),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: valueColor ?? titleColor),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _AuditEntry extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;

  const _AuditEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark
        ? DesignColors.darkTextSecondary
        : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? DesignColors.darkSurfaceElevated
                  : DesignColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: secondaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: secondaryColor)),
              ],
            ),
          ),
          Text(time,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? DesignColors.darkTextTertiary
                      : DesignColors.textTertiary)),
        ],
      ),
    );
  }
}

// ═══════ BRANCH MANAGEMENT SHEET ═══════
class _BranchManagementSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _BranchManagementSheet({required this.scrollController});

  @override
  State<_BranchManagementSheet> createState() => _BranchManagementSheetState();
}

class _BranchManagementSheetState extends State<_BranchManagementSheet> {
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final branches = await getIt<ApiClient>().getBranches();
      if (!mounted) return;
      setState(() {
        _branches = branches.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load branches. Check your connection.';
        _loading = false;
      });
    }
  }

  String? _apiErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        if (message is List && message.isNotEmpty) return message.first.toString();
        return message.toString();
      }
    }
    return null;
  }

  void _showAddBranchDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();
    final phoneController = TextEditingController();
    bool isSaving = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => SettingsDialog(
          title: 'Add Branch',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Branch Name',
                  hintText: 'e.g. Downtown Branch',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Branch Code',
                  hintText: 'e.g. DWT001',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                  hintText: 'e.g. CBD, Nairobi',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  hintText: 'e.g. +254 700 000 000',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: DesignColors.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            SettingsPrimaryButton(
              label: 'Add',
              isLoading: isSaving,
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Branch name is required');
                  return;
                }
                if (codeController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Branch code is required');
                  return;
                }
                setDialogState(() {
                  isSaving = true;
                  error = null;
                });
                try {
                  await getIt<ApiClient>().createBranch(
                    name: nameController.text.trim(),
                    code: codeController.text.trim(),
                    address: addressController.text.trim().isEmpty
                        ? null
                        : addressController.text.trim(),
                    phone: phoneController.text.trim().isEmpty
                        ? null
                        : phoneController.text.trim(),
                  );
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadBranches();
                } catch (e) {
                  setDialogState(() {
                    isSaving = false;
                    error = _apiErrorMessage(e) ??
                        'Could not add branch. Check your connection.';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBranchDialog(Map<String, dynamic> branch) {
    final nameController =
        TextEditingController(text: branch['name'] as String? ?? '');
    final codeController =
        TextEditingController(text: branch['code'] as String? ?? '');
    final addressController =
        TextEditingController(text: branch['address'] as String? ?? '');
    final phoneController =
        TextEditingController(text: branch['phone'] as String? ?? '');
    bool isSaving = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => SettingsDialog(
          title: 'Edit Branch',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: 'Branch Name')),
              const SizedBox(height: 12),
              TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      const InputDecoration(labelText: 'Branch Code')),
              const SizedBox(height: 12),
              TextField(
                  controller: addressController,
                  decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: DesignColors.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            SettingsPrimaryButton(
              label: 'Save',
              isLoading: isSaving,
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Branch name is required');
                  return;
                }
                setDialogState(() {
                  isSaving = true;
                  error = null;
                });
                try {
                  await getIt<ApiClient>().updateBranch(
                    branch['id'] as String,
                    name: nameController.text.trim(),
                    code: codeController.text.trim().isEmpty
                        ? null
                        : codeController.text.trim(),
                    address: addressController.text.trim().isEmpty
                        ? null
                        : addressController.text.trim(),
                    phone: phoneController.text.trim().isEmpty
                        ? null
                        : phoneController.text.trim(),
                  );
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _loadBranches();
                } catch (e) {
                  setDialogState(() {
                    isSaving = false;
                    error = _apiErrorMessage(e) ??
                        'Could not save changes. Check your connection.';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteBranch(Map<String, dynamic> branch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => SettingsDialog(
        title: 'Delete Branch',
        content: Text('Are you sure you want to delete "${branch['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          SettingsPrimaryButton(
            label: 'Delete',
            color: DesignColors.error,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await getIt<ApiClient>().deleteBranch(branch['id'] as String);
      if (!mounted) return;
      _loadBranches();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        _apiErrorMessage(e) ??
            'Could not delete branch. It may have existing sales history.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Branch Management',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text(
                  '${_branches.length} branch${_branches.length == 1 ? '' : 'es'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Couldn\'t load branches',
                        subtitle: _loadError!,
                        iconColor: DesignColors.error,
                        actionLabel: 'Retry',
                        onAction: _loadBranches,
                      )
                    : _branches.isEmpty
                        ? EmptyState(
                            icon: Icons.store_outlined,
                            title: 'No branches yet',
                            subtitle: 'Tap "Add Branch" to create your first one',
                          )
                        : ListView.builder(
                            controller: widget.scrollController,
                            itemCount: _branches.length,
                            itemBuilder: (context, index) {
                              final branch = _branches[index];
                              final isActive = branch['isActive'] as bool? ?? true;
                              return GroupedCard(
                                children: [
                                  SettingsRow(
                                    icon: Icons.store_rounded,
                                    title: branch['name'] as String,
                                    subtitle: (branch['address'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? branch['address'] as String
                                        : (branch['code'] as String? ?? ''),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _StatusBadge(
                                            text: isActive ? 'Active' : 'Inactive',
                                            color: isActive
                                                ? DesignColors.success
                                                : DesignColors.textTertiary),
                                        PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _showEditBranchDialog(branch);
                                            }
                                            if (value == 'delete') {
                                              _deleteBranch(branch);
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit')),
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showAddBranchDialog,
              icon: const Icon(Icons.add_business),
              label: const Text('Add Branch'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
