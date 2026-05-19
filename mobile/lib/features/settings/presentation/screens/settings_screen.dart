import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/local_server_service.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// Settings keys for SharedPreferences
class _SettingsKeys {
  static const autoPrintReceipt = 'setting_auto_print_receipt';
  static const printerName = 'setting_printer_name';
  static const paperWidth = 'setting_paper_width';
  static const notifySales = 'setting_notify_sales';
  static const notifyInventory = 'setting_notify_inventory';
  static const notifySync = 'setting_notify_sync';
  static const biometricEnabled = 'setting_biometric_enabled';
  static const autoLockMinutes = 'setting_auto_lock_minutes';
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final perms = ref.watch(permissionsProvider);
    final syncService = getIt<SyncService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: DesignColors.brand,
                    size: 28,
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

          // ═══════ PHONE SERVER MODE (always at top) ═══════
          const SizedBox(height: 8),
          Text(
            'Phone Server Mode',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DesignColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          _ServerModeTile(),
          _SettingsTile(
            icon: Icons.dns,
            title: 'Backend Server',
            subtitle: 'Set this device as a client of another phone server',
            onTap: () => _showBackendServerSettings(context),
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
            Text(
              'Preferences',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: DesignColors.textSecondary,
                  ),
            ),
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
          Text(
            'Account',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DesignColors.textSecondary,
                ),
          ),
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
          Text(
            'Support',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DesignColors.textSecondary,
                ),
          ),
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
          _SettingsTile(
            icon: Icons.info,
            title: 'About',
            subtitle: 'Version 1.0.0',
            onTap: () => _showAboutInfo(context),
          ),

          // Admin-only section
          if (perms.canManageUsers) ...[
            const SizedBox(height: 16),
            Text(
              'Administration',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: DesignColors.textSecondary,
                  ),
            ),
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
          OutlinedButton.icon(
            onPressed: () => _showLogoutDialog(context, ref),
            icon: const Icon(Icons.logout, color: DesignColors.error),
            label: const Text(
              'Logout',
              style: TextStyle(color: DesignColors.error),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: DesignColors.error),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ===== LOGOUT (FIXED) =====
  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    // Capture the settings screen context BEFORE opening the dialog
    final settingsContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text(
            'Are you sure you want to logout? Any unsynced data will be saved locally.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog first
              await ref.read(authControllerProvider.notifier).logout();
              if (settingsContext.mounted) {
                settingsContext.go('/login');
              }
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: DesignColors.error),
            ),
          ),
        ],
      ),
    );
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
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled =
        prefs.getBool(_SettingsKeys.biometricEnabled) ?? false;
    final autoLockMinutes = prefs.getInt(_SettingsKeys.autoLockMinutes) ?? 5;
    final authService = getIt<AuthService>();
    final biometricAvailable = await authService.isBiometricAvailable();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SecuritySettingsSheet(
        biometricEnabled: biometricEnabled,
        biometricAvailable: biometricAvailable,
        autoLockMinutes: autoLockMinutes,
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
            ListTile(
              leading:
                  const Icon(Icons.email_outlined, color: DesignColors.brand),
              title: const Text('Email Support'),
              subtitle: const Text('johnkimani576@gmail.com'),
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
  void _showAboutInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AboutDialog(
        applicationName: 'Levisa Adventures POS',
        applicationVersion: '1.0.0 (Build 1)',
        applicationLegalese:
            'Licensed for Levisa Adventures. Licence documents: https://drive.google.com/drive/folders/11tFlwbpTixoRIdkrgrlKJAKdGsqqofBX',
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
          Text('© 2026 Levisa Adventures',
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
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: DesignColors.surfaceSubtle,
                          child: const Icon(Icons.person_add,
                              color: DesignColors.textSecondary),
                        ),
                        title: const Text('No other users yet'),
                        subtitle:
                            const Text('Tap + Add to create staff accounts'),
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
                  value: selectedRole,
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
                  children: [
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
  void _checkForUpdates(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
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

    getIt<UpdateCheckService>().checkForUpdates(
      context: context,
      force: true, // Force check since user manually initiated it
    ).then((wasUpdateShown) {
      // If no update was found, close the loading dialog and show a message
      if (context.mounted) {
        Navigator.of(context).pop(); // close the loading dialog
        if (!wasUpdateShown) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You\'re on the latest version! ✅'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  // ===== BACKEND SERVER SETTINGS (Client Mode) =====
  void _showBackendServerSettings(BuildContext context) {
    final storage = getIt<StorageService>();
    final serverIpController =
        TextEditingController(text: storage.getBackendServerIp() ?? '');
    final serverPortController =
        TextEditingController(text: storage.getBackendServerPort().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
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
            Text('Backend Server', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Point this device to a phone server on your network',
                style: const TextStyle(
                    color: DesignColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: serverIpController,
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                hintText: 'e.g. 192.168.1.50',
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: serverPortController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '3000',
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final ip = serverIpController.text.trim();
                  final port =
                      int.tryParse(serverPortController.text.trim()) ?? 3000;
                  if (ip.isEmpty) {
                    _showSnack(context, 'Please enter a server IP address',
                        isError: true);
                    return;
                  }
                  await storage.setBackendServerIp(ip);
                  await storage.setBackendServerPort(port);

                  // Update the API client base URL
                  final apiClient = getIt<ApiClient>();
                  apiClient.setBaseUrl('http://$ip:$port/api/v1');

                  if (!context.mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnack(context, 'Server set to http://$ip:$port');
                },
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
              ),
            ),
            const SizedBox(height: 8),
            // Test connection button
            if (storage.getBackendServerIp() != null)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ip = serverIpController.text.trim();
                    final port =
                        int.tryParse(serverPortController.text.trim()) ?? 3000;
                    _showSnack(context, 'Testing connection...');
                    try {
                      final client = getIt<ApiClient>();
                      client.setBaseUrl('http://$ip:$port/api/v1');
                      await client.getDashboard();
                      if (!context.mounted) return;
                      _showSnack(context, '✅ Connected! Server is online.');
                    } catch (e) {
                      if (!context.mounted) return;
                      _showSnack(context, '❌ Connection failed: $e',
                          isError: true);
                    }
                  },
                  icon: const Icon(Icons.network_check),
                  label: const Text('Test Connection'),
                ),
              ),
            // Clear server setting
            if (storage.getBackendServerIp() != null)
              TextButton.icon(
                onPressed: () async {
                  await storage.setBackendServerIp('');
                  await storage.setBackendServerPort(3000);
                  // Reset to built-in URL
                  final apiClient = getIt<ApiClient>();
                  apiClient.setBaseUrl('http://192.168.100.47:3000/api/v1');
                  if (!context.mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnack(context,
                      'Cleared server setting — using default backend');
                },
                icon: const Icon(Icons.clear, color: DesignColors.error),
                label: const Text('Clear & Use Default',
                    style: TextStyle(color: DesignColors.error)),
              ),
          ],
        ),
      ),
    );
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
            value: _paperWidth,
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
  final int autoLockMinutes;

  const _SecuritySettingsSheet({
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.autoLockMinutes,
  });

  @override
  State<_SecuritySettingsSheet> createState() => _SecuritySettingsSheetState();
}

class _SecuritySettingsSheetState extends State<_SecuritySettingsSheet> {
  late bool _biometricEnabled;
  late int _autoLockMinutes;
  bool _fingerprintEnabled = true;
  bool _faceRecognitionEnabled = true;

  @override
  void initState() {
    super.initState();
    _biometricEnabled = widget.biometricEnabled;
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
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Security', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Biometric Login'),
            subtitle: Text(widget.biometricAvailable
                ? 'Enable biometric authentication'
                : 'Not available on this device'),
            secondary: const Icon(Icons.security),
            value: _biometricEnabled && widget.biometricAvailable,
            onChanged: widget.biometricAvailable
                ? (v) => setState(() => _biometricEnabled = v)
                : null,
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
            trailing: DropdownButton<int>(
              value: _autoLockMinutes,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 min')),
                DropdownMenuItem(value: 5, child: Text('5 min')),
                DropdownMenuItem(value: 15, child: Text('15 min')),
                DropdownMenuItem(value: 30, child: Text('30 min')),
                DropdownMenuItem(value: 0, child: Text('Never')),
              ],
              onChanged: (v) => setState(() => _autoLockMinutes = v ?? 5),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(
                    _SettingsKeys.biometricEnabled, _biometricEnabled);
                await prefs.setInt(
                    _SettingsKeys.autoLockMinutes, _autoLockMinutes);
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
    );
  }
}

// ===== SHARED WIDGETS =====
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DesignColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: DesignColors.textSecondary, size: 20),
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style:
              const TextStyle(fontSize: 12, color: DesignColors.textSecondary),
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
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

// ═══════ SERVER MODE TILE ═══════
class _ServerModeTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerModeTile> createState() => _ServerModeTileState();
}

class _ServerModeTileState extends ConsumerState<_ServerModeTile> {
  bool _serverRunning = false;
  List<String> _localIps = [];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final server = getIt<LocalServerService>();
    final ips = await LocalServerService.getLocalIpAddresses();
    setState(() {
      _serverRunning = server.isRunning;
      _localIps = ips;
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = getIt<LocalServerService>();
    final storage = getIt<StorageService>();
    final serverMode = storage.isServerModeEnabled();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _serverRunning
                    ? DesignColors.success.withValues(alpha: 0.1)
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _serverRunning ? Icons.dns : Icons.dns_outlined,
                color: _serverRunning
                    ? DesignColors.success
                    : DesignColors.textSecondary,
                size: 20,
              ),
            ),
            title: const Text('Server Mode'),
            subtitle: Text(
              _serverRunning
                  ? 'Running on port ${server.port}'
                  : serverMode
                      ? 'Tap to start'
                      : 'Turn on to start the phone server',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_serverRunning)
                  const _StatusBadge(
                      text: 'RUNNING', color: DesignColors.success),
                Switch(
                  value: serverMode,
                  onChanged: (v) async {
                    if (v) {
                      final port = storage.getServerPort();
                      final started = await server.start(port: port);
                      if (started) {
                        await storage.setServerModeEnabled(true);
                        _loadStatus();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Server mode started')),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Failed to start server. Try a different port.'),
                              backgroundColor: DesignColors.error,
                            ),
                          );
                        }
                      }
                    } else {
                      await server.stop();
                      await storage.setServerModeEnabled(false);
                      _loadStatus();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Server mode stopped')),
                        );
                      }
                    }
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          if (_serverRunning && _localIps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 4),
                  const Text('Connect from other devices:',
                      style: TextStyle(
                          fontSize: 12, color: DesignColors.textSecondary)),
                  const SizedBox(height: 4),
                  ..._localIps.map((ip) => Text(
                        'http://$ip:${server.port}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DesignColors.brand),
                      )),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showServerUserManagement(context),
                      icon: const Icon(Icons.people, size: 16),
                      label: const Text('Manage Server Users'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showServerUserManagement(BuildContext context) {
    final db = getIt<AppDatabase>();

    Future<List<Map<String, dynamic>>> _getUsers() async {
      try {
        final result = await db
            .customSelect('SELECT * FROM server_users ORDER BY created_at DESC')
            .get();
        return result
            .map((r) => {
                  'id': r.read<String>('id'),
                  'email': r.read<String>('email'),
                  'firstName': r.read<String>('first_name'),
                  'lastName': r.read<String>('last_name'),
                  'role': r.read<String>('role'),
                  'isActive': r.read<int>('is_active') == 1,
                  'lastLoginAt': r.readNullable<String>('last_login_at'),
                })
            .toList();
      } catch (_) {
        return [];
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) =>
            FutureBuilder<List<Map<String, dynamic>>>(
          future: _getUsers(),
          builder: (ctx, snapshot) {
            final users = snapshot.data ?? [];
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
                              color: DesignColors.surfaceBorder,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Server Users',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddServerUserDialog(context);
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Activate or deactivate user accounts',
                      style: TextStyle(
                          color: DesignColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: users.isEmpty
                        ? const Center(
                            child: Text('No users yet. Add your first user.'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: users.length,
                            itemBuilder: (ctx, i) {
                              final u = users[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: u['isActive'] == true
                                        ? DesignColors.brand
                                            .withValues(alpha: 0.1)
                                        : DesignColors.surfaceSubtle,
                                    child: Text(
                                      (u['firstName'] as String).isNotEmpty
                                          ? (u['firstName'] as String)[0]
                                              .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: u['isActive'] == true
                                            ? DesignColors.brand
                                            : DesignColors.textTertiary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                      '${u['firstName']} ${u['lastName']}'),
                                  subtitle:
                                      Text('${u['email']}  •  ${u['role']}'),
                                  trailing: Switch(
                                    value: u['isActive'] == true,
                                    onChanged: (active) async {
                                      await db.customStatement(
                                        'UPDATE server_users SET is_active = ? WHERE id = ?',
                                        [
                                          Variable.withInt(active ? 1 : 0),
                                          Variable.withString(u['id'] as String)
                                        ],
                                      );
                                      setState(() {});
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                            content: Text(active
                                                ? '${u['firstName']} activated'
                                                : '${u['firstName']} deactivated'),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showAddServerUserDialog(BuildContext context) {
    final emailController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final passwordController = TextEditingController();
    final pinController = TextEditingController();
    String selectedRole = 'CASHIER';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Server User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                      labelText: 'First Name', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                      labelText: 'Last Name', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Email', prefixIcon: Icon(Icons.email)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Password', prefixIcon: Icon(Icons.lock)),
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
                      counterText: ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                      labelText: 'Role', prefixIcon: Icon(Icons.badge)),
                  items: const [
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                    DropdownMenuItem(value: 'MANAGER', child: Text('Manager')),
                    DropdownMenuItem(
                        value: 'SUPERVISOR', child: Text('Supervisor')),
                    DropdownMenuItem(value: 'CASHIER', child: Text('Cashier')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedRole = v ?? 'CASHIER'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (emailController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Email and password are required'),
                        backgroundColor: DesignColors.error),
                  );
                  return;
                }
                final db = getIt<AppDatabase>();
                final passwordHash = sha256
                    .convert(utf8.encode(passwordController.text))
                    .toString();
                final pinHash = pinController.text.length == 4
                    ? sha256.convert(utf8.encode(pinController.text)).toString()
                    : null;
                final id = const Uuid().v4();

                try {
                  await db.customInsert(
                    'INSERT INTO server_users (id, email, password_hash, pin_hash, first_name, last_name, role, is_active, created_at, updated_at) '
                    'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
                    variables: [
                      Variable.withString(id),
                      Variable.withString(emailController.text.trim()),
                      Variable.withString(passwordHash),
                      pinHash != null
                          ? Variable.withString(pinHash)
                          : Variable.withString(''),
                      Variable.withString(firstNameController.text.trim()),
                      Variable.withString(lastNameController.text.trim()),
                      Variable.withString(selectedRole),
                      Variable.withString(DateTime.now().toIso8601String()),
                      Variable.withString(DateTime.now().toIso8601String()),
                    ],
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'User ${firstNameController.text.trim()} added as $selectedRole')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: DesignColors.error),
                    );
                  }
                }
              },
              child: const Text('Add User'),
            ),
          ],
        ),
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
                          leading: CircleAvatar(
                            backgroundColor: DesignColors.brand,
                            child: const Icon(Icons.store,
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
                                  if (value == 'edit')
                                    _showEditBranchDialog(branch);
                                  if (value == 'delete') _deleteBranch(branch);
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
