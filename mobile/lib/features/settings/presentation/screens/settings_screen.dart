import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/database/app_database.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Settings keys for SharedPreferences
class _SettingsKeys {
  static const autoPrintReceipt = 'setting_auto_print_receipt';
  static const printerName = 'setting_printer_name';
  static const paperWidth = 'setting_paper_width';
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
                subtitle: 'Manage staff & roles',
                onTap: () => _showUserManagement(context),
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
                onTap: () => _showTaxRateDialog(context),
              ),
              SettingsRow(
                icon: Icons.download_rounded,
                title: 'Data Export',
                subtitle: 'Export sales & reports',
                onTap: () => _showDataExport(context),
              ),
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
                      _showUserGuide(context);
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

  void _showUserGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        title: 'User Guide',
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. Making a Sale',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text(
                  '• Go to POS tab\n• Search or browse for products\n• Tap a product and set quantity\n• Review cart and proceed to payment\n• Choose payment method and complete'),
              SizedBox(height: 16),
              Text('2. Managing Products',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text(
                  '• Go to Products tab\n• Tap + to add new products\n• Long-press to delete\n• Tap to edit details\n• Use the category button to manage categories'),
              SizedBox(height: 16),
              Text('3. Reports',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text(
                  '• Go to Reports tab\n• View daily/weekly/monthly sales\n• Track revenue and top products'),
              SizedBox(height: 16),
              Text('4. Inventory',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 4),
              Text(
                  '• Go to Inventory tab\n• Check stock levels\n• Receive new stock deliveries'),
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
        return AboutDialog(
        applicationName: 'Point of Sale',
        applicationVersion: _formatReleaseName(info.version),
        applicationLegalese:
            'Licensed for your company workspace. Contact your administrator for licence documents.',
        applicationIcon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: DesignColors.brand,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront, color: Colors.white, size: 28),
        ),
        children: [
          Text(
            'A complete point-of-sale system for managing sales, inventory, and business operations.',
            style: TextStyle(color: titleColor),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Built by Arche Axon Intelligence',
                    style: TextStyle(
                        color: secondaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SelectableText(
                  'Licence folder: https://drive.google.com/drive/folders/11tFlwbpTixoRIdkrgrlKJAKdGsqqofBX',
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text('© 2026 POS Platform',
                    style: TextStyle(color: secondaryColor, fontSize: 12)),
              ],
            ),
          ),
        ],
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

  // ===== ADMIN-ONLY: USER MANAGEMENT =====
  void _showUserManagement(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final border =
              isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
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
                  Text('User Management',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddUserDialog(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider) ?? {};
                        final role = AppRole.fromString(
                            user['role'] as String? ?? 'CASHIER');
                        return _UserTile(
                          name: user['name'] as String? ?? 'User',
                          email: user['email'] as String? ?? '',
                          role: role,
                          isCurrentUser: true,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _RoleAccessSummary(),
                    const SizedBox(height: 12),
                    // Placeholder for additional users
                    const GroupedCard(
                      margin: EdgeInsets.zero,
                      children: [
                        SettingsRow(
                          icon: Icons.person_add_rounded,
                          title: 'No other users yet',
                          subtitle: 'Tap + Add to create staff accounts',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          );
        },
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final pinController = TextEditingController();
    String selectedRole = 'seller';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => SettingsDialog(
          title: 'Add New User',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'PIN (4 digits)',
                    prefixIcon: Icon(Icons.lock),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'seller', child: Text('Seller')),
                    DropdownMenuItem(
                        value: 'stock_keeper', child: Text('Stock Keeper')),
                    DropdownMenuItem(
                        value: 'store_manager', child: Text('Store Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedRole = v ?? 'seller'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            SettingsPrimaryButton(
              label: 'Add User',
              onPressed: () {
                if (nameController.text.isEmpty ||
                    pinController.text.length != 4) {
                  _showSnack(context, 'Fill all fields (PIN must be 4 digits)',
                      isError: true);
                  return;
                }
                Navigator.pop(dialogContext);
                _showSnack(context,
                    '${nameController.text} added as ${AppRole.fromString(selectedRole).label}');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ===== ADMIN-ONLY: BRANCH MANAGEMENT =====
  // ===== ADMIN-ONLY: TAX RATE =====
  void _showTaxRateDialog(BuildContext context) {
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
  void _showDataExport(BuildContext context) {
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
              subtitle: 'CSV format',
              onTap: () async {
                Navigator.pop(context);
                await _exportSalesData(context);
              },
            ),
            SettingsRow(
              icon: Icons.inventory_rounded,
              title: 'Export Inventory',
              subtitle: 'CSV format',
              onTap: () async {
                Navigator.pop(context);
                await _exportInventory(context);
              },
            ),
            SettingsRow(
              icon: Icons.category_rounded,
              title: 'Export Products',
              subtitle: 'CSV format',
              onTap: () async {
                Navigator.pop(context);
                await _exportProducts(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSalesData(BuildContext context) async {
    try {
      _showSnack(context, 'Generating sales export...');
      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      final sales = await db.getSalesByDateRange(
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month, now.day, 23, 59, 59),
      );

      final buffer = StringBuffer();
      buffer.writeln(
          'Receipt Number,Date,Subtotal,Discount,Tax,Total,Payment Method,Cashier ID,Branch ID,Status');
      for (final s in sales) {
        buffer.writeln(
            '${_csvEscape(s.receiptNumber)},${s.createdAt.toIso8601String()},'
            '${s.subtotal},${s.discount},${s.tax},${s.total},'
            '${_csvEscape(s.paymentMethod)},${_csvEscape(s.cashierId)},'
            '${_csvEscape(s.branchId)},${_csvEscape(s.status)}');
      }

      final path = await _saveExportFile('sales_export', buffer.toString());
      if (!context.mounted) return;
      await _shareExportFile(context, path, '${sales.length} sales records');
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  Future<void> _exportInventory(BuildContext context) async {
    try {
      _showSnack(context, 'Generating inventory export...');
      final db = getIt<AppDatabase>();
      final data = await db.getInventoryReport();

      final buffer = StringBuffer();
      buffer.writeln(
          'Product ID,Name,SKU,Category,Price,Cost Price,Stock,Min Stock');
      for (final d in data) {
        buffer.writeln(
            '${_csvEscape(d['id'] as String)},${_csvEscape(d['name'] as String)},'
            '${_csvEscape(d['sku'] as String)},${_csvEscape(d['categoryName'] as String)},'
            '${d['price']},${d['costPrice']},${d['stock']},${d['minStock']}');
      }

      final path = await _saveExportFile('inventory_export', buffer.toString());
      if (!context.mounted) return;
      await _shareExportFile(context, path, '${data.length} inventory items');
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  Future<void> _exportProducts(BuildContext context) async {
    try {
      _showSnack(context, 'Generating products export...');
      final db = getIt<AppDatabase>();
      final products = await db.getAllProducts();

      final buffer = StringBuffer();
      buffer.writeln('ID,SKU,Name,Category ID,Price,Cost Price,Unit,Active');
      for (final p in products) {
        buffer.writeln(
            '${_csvEscape(p.id)},${_csvEscape(p.sku)},${_csvEscape(p.name)},'
            '${_csvEscape(p.categoryId)},${p.price},${p.costPrice ?? 0},'
            '${_csvEscape(p.unit)},${p.isActive}');
      }

      final path = await _saveExportFile('products_export', buffer.toString());
      if (!context.mounted) return;
      await _shareExportFile(context, path, '${products.length} products');
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
    }
  }

  /// Opens the OS share sheet for a generated export file. Exports are
  /// written to app-private storage (invisible to the user's Files app),
  /// so a raw success message with a filesystem path would be a dead end —
  /// sharing is the only way the user can actually get the file out to
  /// email, WhatsApp, Drive, etc.
  Future<void> _shareExportFile(
      BuildContext context, String path, String description) async {
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'Axon POS export',
        text: 'Exported $description',
      );
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Export saved but could not open share sheet: $e');
      }
    }
  }

  Future<String> _saveExportFile(String prefix, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/${prefix}_$timestamp.csv');
    await file.writeAsString(content);
    return file.path;
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
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
  final String paperWidth;

  const _PrinterSettingsSheet({
    required this.autoPrint,
    required this.printerName,
    required this.paperWidth,
  });

  @override
  State<_PrinterSettingsSheet> createState() => _PrinterSettingsSheetState();
}

class _PrinterSettingsSheetState extends State<_PrinterSettingsSheet> {
  late bool _autoPrint;
  late String _paperWidth;
  late TextEditingController _printerNameController;

  @override
  void initState() {
    super.initState();
    _autoPrint = widget.autoPrint;
    _paperWidth = widget.paperWidth;
    _printerNameController = TextEditingController(text: widget.printerName);
  }

  @override
  void dispose() {
    _printerNameController.dispose();
    super.dispose();
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
            TextField(
              controller: _printerNameController,
              decoration: InputDecoration(
                labelText: 'Printer Name / Address',
                hintText: 'e.g. BT_Printer_58mm',
                prefixIcon: const Icon(Icons.print_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showGlassSnackBar(
                          context, 'Searching for Bluetooth printers...',
                          icon: Icons.bluetooth_searching_rounded,
                          color: DesignColors.info);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Scan Printers'),
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
                      await prefs.setString(_SettingsKeys.printerName,
                          _printerNameController.text);
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
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Notification settings saved')),
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
  bool _fingerprintEnabled = true;
  bool _faceRecognitionEnabled = true;

  @override
  void initState() {
    super.initState();
    _biometricEnabled = widget.biometricEnabled;
    _requireUnlockOnResume = widget.requireUnlockOnResume;
    _autoLockMinutes = widget.autoLockMinutes;
    _loadBiometricPrefs();
  }

  Future<void> _loadBiometricPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fingerprintEnabled =
          prefs.getBool('setting_fingerprint_enabled') ?? true;
      _faceRecognitionEnabled =
          prefs.getBool('setting_face_recognition_enabled') ?? true;
    });
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
                  enabled: widget.biometricAvailable,
                  trailing: Switch(
                    value: _biometricEnabled && widget.biometricAvailable,
                    activeThumbColor: DesignColors.accent,
                    onChanged: widget.biometricAvailable
                        ? (v) => setState(() => _biometricEnabled = v)
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
            if (_biometricEnabled && widget.biometricAvailable) ...[
              const SettingsGroupLabel('Biometric Methods'),
              GroupedCard(
                children: [
                  SettingsRow(
                    icon: Icons.fingerprint_rounded,
                    title: 'Fingerprint',
                    subtitle: 'Use fingerprint to sign in',
                    trailing: Switch(
                      value: _fingerprintEnabled,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) =>
                          setState(() => _fingerprintEnabled = v),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.face_rounded,
                    title: 'Face Recognition',
                    subtitle: 'Use face recognition to sign in',
                    trailing: Switch(
                      value: _faceRecognitionEnabled,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) =>
                          setState(() => _faceRecognitionEnabled = v),
                    ),
                  ),
                ],
              ),
            ],
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
                  final storage = getIt<StorageService>();
                  final prefs = await SharedPreferences.getInstance();
                  await storage.setBiometricEnabled(_biometricEnabled);
                  await storage
                      .setRequireUnlockOnResume(_requireUnlockOnResume);
                  await storage.setAutoLockMinutes(_autoLockMinutes);
                  await prefs.setBool(
                      'setting_fingerprint_enabled', _fingerprintEnabled);
                  await prefs.setBool('setting_face_recognition_enabled',
                      _faceRecognitionEnabled);
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
  const _InfoRow(this.label, this.value);

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
                    color: titleColor),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String name;
  final String email;
  final AppRole role;
  final bool isCurrentUser;

  const _UserTile({
    required this.name,
    required this.email,
    required this.role,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: DesignColors.accent.withValues(alpha: 0.1),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: DesignColors.accent, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
            if (isCurrentUser) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('You',
                    style: TextStyle(
                        fontSize: 10,
                        color: DesignColors.accent,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        subtitle: Text('$email  •  ${role.label}'),
        trailing: isCurrentUser
            ? null
            : IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
              ),
      ),
    );
  }
}

class _RoleAccessSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const roles = [
      ('Seller', 'POS, own sales, and basic settings'),
      ('Stock Keeper', 'Seller access plus inventory and product viewing'),
      (
        'Store Manager',
        'Product editing, reports, discounts, sync, and printer settings'
      ),
      (
        'Admin',
        'All access including users, branches, finance, audit, and exports'
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DesignColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: DesignColors.accent, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  'Role access levels',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...roles.map(
              (role) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: DesignColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: '${role.$1}: ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: role.$2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
