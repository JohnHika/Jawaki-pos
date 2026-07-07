import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

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

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Profile Card
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 12,
            blur: 10,
            tint: Colors.transparent,
            borderColor: DesignColors.surfaceBorder,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: DesignColors.brand.withValues(alpha: 0.15),
                  child: Text(
                    _initialFor(user?['name'] ?? user?['email']),
                    style: const TextStyle(
                      color: DesignColors.brand,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
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
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?['email'] ?? '',
                        style: const TextStyle(
                          color: DesignColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: DesignColors.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (user?['role'] ?? 'CASHIER').toString().toUpperCase(),
                          style: const TextStyle(
                            color: DesignColors.brand,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sync Status (manager+)
          if (perms.canConfigureSync)
            FutureBuilder(
              future: syncService.getStats(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return _SettingsTile(
                  icon: Icons.sync,
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

          if (perms.canConfigurePrinter || perms.canSeeAppearance) ...[
            const SizedBox(height: 16),
            const _SettingsSectionLabel('Preferences'),
            const SizedBox(height: 8),
          ],

          // Printer — manager+
          if (perms.canConfigurePrinter)
            _SettingsTile(
              icon: Icons.print,
              title: 'Printer Settings',
              subtitle: 'Configure receipt printer',
              onTap: () => _showPrinterSettings(context),
            ),
          // Notifications — manager+
          if (perms.canConfigureNotifications)
            _SettingsTile(
              icon: Icons.notifications,
              title: 'Notifications',
              subtitle: 'Manage notification preferences',
              onTap: () => _showNotificationSettings(context),
            ),
          // Appearance — everyone
          if (perms.canSeeAppearance)
            _SettingsTile(
              icon: Icons.dark_mode,
              title: 'Appearance',
              subtitle: 'Light / Dark mode',
              onTap: () => _showAppearanceSettings(context),
            ),

          const SizedBox(height: 16),
          const _SettingsSectionLabel('Account'),
          const SizedBox(height: 8),

          _SettingsTile(
            icon: Icons.lock,
            title: 'Change PIN',
            subtitle: 'Update your quick login PIN',
            onTap: () => _showChangePinDialog(context),
          ),
          _SettingsTile(
            icon: Icons.security,
            title: 'Security',
            subtitle: 'Biometrics & auto-lock',
            onTap: () => _showSecuritySettings(context),
          ),

          const SizedBox(height: 16),
          const _SettingsSectionLabel('Support'),
          const SizedBox(height: 8),

          _SettingsTile(
            icon: Icons.help,
            title: 'Help & Support',
            subtitle: 'Get help with the app',
            onTap: () => _showHelpSupport(context),
          ),
          _SettingsTile(
            icon: Icons.system_update,
            title: 'Check for Updates',
            subtitle: 'See if a newer version is available',
            onTap: () => _checkForUpdates(context),
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '1.0.3';
              return _SettingsTile(
                icon: Icons.info,
                title: 'About',
                subtitle: 'Version $version',
                onTap: () => _showAboutInfo(context),
              );
            },
          ),

          // Admin-only section
          if (perms.canManageUsers) ...[
            const SizedBox(height: 16),
            const _SettingsSectionLabel('Administration'),
            const SizedBox(height: 8),
            _SettingsTile(
              icon: Icons.people,
              title: 'User Management',
              subtitle: 'Manage staff & roles',
              onTap: () => _showUserManagement(context),
            ),
            _SettingsTile(
              icon: Icons.store,
              title: 'Branch Management',
              subtitle: 'Manage store locations',
              onTap: () => _showBranchManagement(context),
            ),
            _SettingsTile(
              icon: Icons.percent_rounded,
              title: 'Tax Rate',
              subtitle: getIt<AuthService>().taxRatePercent > 0
                  ? '${getIt<AuthService>().taxRatePercent.toStringAsFixed(getIt<AuthService>().taxRatePercent % 1 == 0 ? 0 : 1)}% applied to every sale'
                  : 'No tax applied to sales',
              onTap: () => _showTaxRateDialog(context),
            ),
            _SettingsTile(
              icon: Icons.download,
              title: 'Data Export',
              subtitle: 'Export sales & reports',
              onTap: () => _showDataExport(context),
            ),
            _SettingsTile(
              icon: Icons.history,
              title: 'Audit Trail',
              subtitle: 'View system activity log',
              onTap: () => _showAuditTrail(context),
            ),
          ],

          const SizedBox(height: 24),

          // Logout Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context, ref),
              icon: const Icon(Icons.logout, color: DesignColors.error),
              label: const Text(
                'Logout',
                style: TextStyle(
                  color: DesignColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: DesignColors.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: DesignColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Sync Settings',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            FutureBuilder(
              future: syncService.getStats(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                final storage = getIt<StorageService>();
                final lastSync = storage.getLastSyncAt();
                return Column(
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
              child: FilledButton.icon(
                onPressed: () {
                  syncService.syncPendingEvents();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Syncing...'),
                        duration: Duration(seconds: 2)),
                  );
                },
                icon: const Icon(Icons.sync),
                label: const Text('Sync Now'),
              ),
            ),
            const SizedBox(height: 8),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final currentMode = ref.watch(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Theme.of(ctx).dividerColor,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Appearance', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.light_mode),
                title: const Text('Light Mode'),
                trailing: currentMode == ThemeMode.light
                    ? const Icon(Icons.check_circle, color: DesignColors.brand)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.light);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Dark Mode'),
                trailing: currentMode == ThemeMode.dark
                    ? const Icon(Icons.check_circle, color: DesignColors.brand)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.dark);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('System Default'),
                subtitle: const Text('Follow device theme'),
                trailing: currentMode == ThemeMode.system
                    ? const Icon(Icons.check_circle, color: DesignColors.brand)
                    : null,
                onTap: () {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(ThemeMode.system);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }

  // ===== CHANGE PIN =====
  void _showChangePinDialog(BuildContext context) {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final currentPin = currentPinController.text;
              final newPin = newPinController.text;
              final confirmPin = confirmPinController.text;

              if (currentPin.length != 4) {
                _showSnack(context, 'Enter your current 4-digit PIN',
                    isError: true);
                return;
              }
              if (newPin.length != 4) {
                _showSnack(context, 'New PIN must be 4 digits', isError: true);
                return;
              }
              if (newPin != confirmPin) {
                _showSnack(context, 'PINs do not match', isError: true);
                return;
              }

              final storage = getIt<StorageService>();
              await storage.savePinHash(newPin);
              if (!context.mounted || !dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              _showSnack(context, 'PIN changed successfully');
            },
            child: const Text('Change PIN'),
          ),
        ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: DesignColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Help & Support',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            const ListTile(
              leading: Icon(Icons.email_outlined, color: DesignColors.brand),
              title: Text('Email Support'),
              subtitle: Text('johnkimani576@gmail.com'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.phone_outlined, color: DesignColors.brand),
              title: const Text('Phone Support'),
              subtitle: const Text('0742126582'),
              onTap: () {},
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: const Text('FAQ'),
              subtitle: const Text('Frequently asked questions'),
              onTap: () {
                Navigator.pop(context);
                _showFAQ(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('User Guide'),
              subtitle: const Text('How to use the POS system'),
              onTap: () {
                Navigator.pop(context);
                _showUserGuide(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFAQ(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FAQ'),
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
      builder: (context) => AlertDialog(
        title: const Text('User Guide'),
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
      builder: (context) => AboutDialog(
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
        children: const [
          Text(
              'A complete point-of-sale system for managing sales, inventory, and business operations.'),
          SizedBox(height: 12),
          Text('Built by Arche Axon Intelligence',
              style:
                  TextStyle(color: DesignColors.textSecondary, fontSize: 12)),
          SizedBox(height: 8),
          SelectableText(
            'Licence folder: https://drive.google.com/drive/folders/11tFlwbpTixoRIdkrgrlKJAKdGsqqofBX',
            style: TextStyle(color: DesignColors.textSecondary, fontSize: 12),
          ),
          Text('© 2026 POS Platform',
              style:
                  TextStyle(color: DesignColors.textSecondary, fontSize: 12)),
        ],
      ),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: DesignColors.surfaceBorder,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('User Management',
                      style: Theme.of(context).textTheme.titleLarge),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddUserDialog(context);
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                    const Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: DesignColors.surfaceSubtle,
                          child: Icon(Icons.person_add,
                              color: DesignColors.textSecondary),
                        ),
                        title: Text('No other users yet'),
                        subtitle: Text('Tap + Add to create staff accounts'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New User'),
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
            FilledButton(
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
              child: const Text('Add User'),
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
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Tax Rate'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the VAT/sales tax percentage applied to every sale. Leave at 0 to charge no tax.',
                style: TextStyle(
                    fontSize: 13, color: DesignColors.textSecondary),
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show tax on receipt'),
                subtitle: const Text(
                  'Print the tax amount as its own line on printed receipts',
                  style: TextStyle(fontSize: 12),
                ),
                value: showOnReceipt,
                onChanged: (value) =>
                    setDialogState(() => showOnReceipt = value),
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
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
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
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBranchManagement(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Data Export', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ListTile(
              leading:
                  const Icon(Icons.receipt_long, color: DesignColors.brand),
              title: const Text('Export Sales Data'),
              subtitle: const Text('CSV format'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _exportSalesData(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory, color: DesignColors.brand),
              title: const Text('Export Inventory'),
              subtitle: const Text('CSV format'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _exportInventory(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category, color: DesignColors.brand),
              title: const Text('Export Products'),
              subtitle: const Text('CSV format'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                Navigator.pop(context);
                await _exportProducts(context);
              },
            ),
            const SizedBox(height: 8),
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
      if (context.mounted) {
        _showSnack(
            context, 'Sales exported (${sales.length} records) to $path');
      }
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
      if (context.mounted) {
        _showSnack(
            context, 'Inventory exported (${data.length} items) to $path');
      }
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
      if (context.mounted) {
        _showSnack(
            context, 'Products exported (${products.length} items) to $path');
      }
    } catch (e) {
      if (context.mounted) _showSnack(context, 'Export failed: $e');
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: DesignColors.surfaceBorder,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Audit Trail',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Recent system activity',
                  style: TextStyle(color: DesignColors.textSecondary)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: const [
                    _AuditEntry(
                      icon: Icons.login,
                      title: 'Session Started',
                      subtitle: 'Logged in successfully',
                      time: 'Just now',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
                      color: DesignColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Printer Settings',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _printerNameController,
            decoration: const InputDecoration(
              labelText: 'Printer Name / Address',
              hintText: 'e.g. BT_Printer_58mm',
              prefixIcon: Icon(Icons.print),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _paperWidth,
            decoration: const InputDecoration(
              labelText: 'Paper Width',
              prefixIcon: Icon(Icons.straighten),
            ),
            items: const [
              DropdownMenuItem(value: '58mm', child: Text('58mm (Small)')),
              DropdownMenuItem(value: '80mm', child: Text('80mm (Standard)')),
            ],
            onChanged: (v) => setState(() => _paperWidth = v ?? '58mm'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Auto-print receipts'),
            subtitle: const Text('Print receipt after each sale'),
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Searching for Bluetooth printers...')),
                    );
                  },
                  child: const Text('Scan Printers'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(
                        _SettingsKeys.autoPrintReceipt, _autoPrint);
                    await prefs.setString(
                        _SettingsKeys.printerName, _printerNameController.text);
                    await prefs.setString(
                        _SettingsKeys.paperWidth, _paperWidth);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Printer settings saved')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
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
          20,
          20,
          24 + MediaQuery.of(context).padding.bottom,
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
                        color: DesignColors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Notifications',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Sales Alerts'),
              subtitle: const Text('Get notified for completed sales'),
              secondary: const Icon(Icons.point_of_sale),
              value: _notifySales,
              onChanged: (v) => setState(() => _notifySales = v),
            ),
            SwitchListTile(
              title: const Text('Inventory Alerts'),
              subtitle: const Text('Low stock and reorder reminders'),
              secondary: const Icon(Icons.inventory),
              value: _notifyInventory,
              onChanged: (v) => setState(() => _notifyInventory = v),
            ),
            SwitchListTile(
              title: const Text('Sync Alerts'),
              subtitle: const Text('Notify when sync completes or fails'),
              secondary: const Icon(Icons.sync),
              value: _notifySync,
              onChanged: (v) => setState(() => _notifySync = v),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_SettingsKeys.notifySales, _notifySales);
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
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
          ],
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
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
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
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Security', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Biometric Login'),
              subtitle: Text(widget.biometricAvailable
                  ? 'Use device fingerprint, face, PIN, or pattern to unlock'
                  : 'Not available on this device'),
              secondary: const Icon(Icons.security),
              value: _biometricEnabled && widget.biometricAvailable,
              onChanged: widget.biometricAvailable
                  ? (v) => setState(() => _biometricEnabled = v)
                  : null,
            ),
            SwitchListTile(
              title: const Text('Require unlock when app reopens'),
              subtitle:
                  const Text('Ask for authentication after leaving the app'),
              secondary: const Icon(Icons.lock_clock_rounded),
              value: _requireUnlockOnResume,
              onChanged: (v) => setState(() => _requireUnlockOnResume = v),
            ),
            if (_biometricEnabled && widget.biometricAvailable) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text('Biometric Methods',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                title: const Text('Fingerprint'),
                subtitle: const Text('Use fingerprint to sign in'),
                secondary: const Icon(Icons.fingerprint),
                value: _fingerprintEnabled,
                onChanged: (v) => setState(() => _fingerprintEnabled = v),
              ),
              SwitchListTile(
                title: const Text('Face Recognition'),
                subtitle: const Text('Use face recognition to sign in'),
                secondary: const Icon(Icons.face),
                value: _faceRecognitionEnabled,
                onChanged: (v) => setState(() => _faceRecognitionEnabled = v),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Auto-lock after'),
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ===== SHARED WIDGETS =====
class _SettingsSectionLabel extends StatelessWidget {
  final String label;

  const _SettingsSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: DesignColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListCard(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: DesignColors.brandSubtle,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: DesignColors.brand, size: 20),
      ),
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(label,
                style: const TextStyle(color: DesignColors.textSecondary),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: DesignColors.brand.withValues(alpha: 0.1),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: DesignColors.brand, fontWeight: FontWeight.bold),
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
                  color: DesignColors.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('You',
                    style: TextStyle(
                        fontSize: 10,
                        color: DesignColors.brand,
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

    return Card(
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
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: DesignColors.brand, size: 18),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: DesignColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: DesignColors.textSecondary),
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
                    style: const TextStyle(
                        fontSize: 12, color: DesignColors.textSecondary)),
              ],
            ),
          ),
          Text(time,
              style: const TextStyle(
                  fontSize: 11, color: DesignColors.textTertiary)),
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

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final db = getIt<AppDatabase>();
    await db.createBranchesTable();
    final branches = await db.getBranches();
    setState(() {
      // Always include Main Branch as default
      if (branches.isEmpty) {
        _branches = [
          {
            'id': 'branch-main',
            'name': 'Main Branch',
            'location': 'Kamukunji, Nairobi',
            'phone': '',
            'isActive': true,
            'createdAt': DateTime.now().toIso8601String(),
          },
        ];
      } else {
        _branches = branches;
      }
      _loading = false;
    });
  }

  void _showAddBranchDialog() {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Branch'),
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
              controller: locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  locationController.text.trim().isEmpty) {
                return;
              }
              final db = getIt<AppDatabase>();
              final id = const Uuid().v4();
              await db.insertBranch(
                id,
                nameController.text.trim(),
                locationController.text.trim(),
                phoneController.text.trim(),
              );
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              _loadBranches();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditBranchDialog(Map<String, dynamic> branch) {
    final nameController =
        TextEditingController(text: branch['name'] as String);
    final locationController =
        TextEditingController(text: branch['location'] as String);
    final phoneController =
        TextEditingController(text: branch['phone'] as String);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Branch Name')),
            const SizedBox(height: 12),
            TextField(
                controller: locationController,
                decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 12),
            TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final db = getIt<AppDatabase>();
              await db.updateBranch(
                branch['id'] as String,
                nameController.text.trim(),
                locationController.text.trim(),
                phoneController.text.trim(),
              );
              if (!mounted || !ctx.mounted) return;
              Navigator.pop(ctx);
              _loadBranches();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(Map<String, dynamic> branch) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Branch'),
        content: Text('Are you sure you want to delete "${branch['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await getIt<AppDatabase>().deleteBranch(branch['id'] as String);
      if (!mounted) return;
      _loadBranches();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Branch Management',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(
                  '${_branches.length} branch${_branches.length == 1 ? '' : 'es'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: widget.scrollController,
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: DesignColors.brand,
                            child: Icon(Icons.store,
                                color: Colors.white, size: 20),
                          ),
                          title: Text(branch['name'] as String),
                          subtitle: Text(branch['location'] as String),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _StatusBadge(
                                  text: 'Active', color: DesignColors.success),
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
                                      value: 'edit', child: Text('Edit')),
                                  const PopupMenuItem(
                                      value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                        ),
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
