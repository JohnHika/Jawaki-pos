import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/theme/share_format_sheet.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/services/receipt_printer_service.dart';
import '../../../../core/services/print_queue_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/services/local_archive_import_service.dart';
import '../../../../core/services/local_archive_export_service.dart';
import '../../../../core/services/local_portable_backup_service.dart';
import '../../../../core/widgets/release_notes.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/utils/format.dart';
import '../widgets/settings_layout.dart';
import '../widgets/living_icon_card.dart';

// Package metadata is immutable for the life of the installed build. Cache it
// so rebuilding Settings does not repeatedly cross the platform channel.
final Future<PackageInfo> _settingsPackageInfo = PackageInfo.fromPlatform();

// Settings keys for SharedPreferences. Printer keys delegate to
// PrinterSettingsKeys (receipt_printer_service.dart) so this screen and
// receipt_screen.dart's print action always agree on where those live.
class _SettingsKeys {
  static const autoPrintReceipt = PrinterSettingsKeys.autoPrint;
  static const printerName = PrinterSettingsKeys.printerName;
  static const printerMacAddress = PrinterSettingsKeys.printerMacAddress;
  static const paperWidth = PrinterSettingsKeys.paperWidth;
  static const notifySales = NotificationService.keyNotifySales;
  static const notifyInventory = NotificationService.keyNotifyInventory;
  static const notifySync = NotificationService.keyNotifySync;
}

String _roleLabel(dynamic role) {
  final raw = role?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Cashier';
  final words = raw.toLowerCase().split(RegExp(r'[_\s]+'));
  return words
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _companyCodeFor(Map<String, dynamic>? user) {
  final tenant = user?['tenant'];
  final tenantMap =
      tenant is Map<String, dynamic> ? tenant : const <String, dynamic>{};
  String? storedSlug;
  try {
    storedSlug = getIt<StorageService>().getTenantSlug();
  } catch (_) {
    storedSlug = null;
  }
  for (final value in [user?['tenantSlug'], tenantMap['slug'], storedSlug]) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text.toUpperCase();
  }
  return '';
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final perms = ref.watch(permissionsProvider);
    final identity = ref.watch(tenantIdentityProvider);
    // Watch the stream so the chip updates live, but read the service for the
    // value: the provider reads false until its first event, which made a
    // connected phone briefly show "Offline".
    ref.watch(isOnlineProvider);
    final isOnline = getIt<ConnectivityService>().isOnline;
    final themeMode = ref.watch(themeModeProvider);
    final isLocalWorkspace = getIt<AuthService>().isLocalWorkspace;
    final isLocalWorkspaceOwner = getIt<AuthService>().isLocalWorkspaceOwner;

    final legacyRole = user?['role']?.toString().toUpperCase() ?? '';
    // The billing and plan APIs intentionally enforce the legacy ADMIN role
    // today. Keep the menu honest until those endpoints are fully migrated to
    // granular permission keys.
    final isBillingAdmin = legacyRole == 'ADMIN';
    // Keep layout access tied to the same granular permission enforced by
    // BusinessLayoutScreen instead of billing's legacy role check.
    final canManageBusinessLayout = perms.has('branches.tenant.update');

    final taxPercent = getIt<AuthService>().taxRatePercent;
    final taxSubtitle = taxPercent > 0
        ? '${taxPercent.toStringAsFixed(taxPercent % 1 == 0 ? 0 : 1)}% tax is added to sales'
        : 'Set the tax charged on sales and shown on receipts';

    final themeLabel = switch (themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Auto',
    };

    final sections = <SettingsSection>[
      SettingsSection(
        id: 'business',
        title: 'My business',
        entries: [
          if (canManageBusinessLayout)
            SettingsEntry(
              id: 'business-layout',
              icon: Icons.tune_rounded,
              title: 'Layout actions',
              subtitle: 'Shape Counterbase around your shop and daily work',
              keywords: const [
                'layout action',
                'industry',
                'bookshop',
                'kamukunji',
                'wholesale',
                'shortcuts',
                'customize',
                'show',
                'hide',
                'work areas',
                'navigation',
              ],
              onTap: () => context.push('/settings/business-layout'),
            ),
          if (!isLocalWorkspace &&
              (isBillingAdmin || perms.has('users.create')))
            SettingsEntry(
              id: 'workspace-setup',
              icon: Icons.checklist_rounded,
              title: 'Workspace setup',
              subtitle: 'Review business, branch, team, catalog and payouts',
              keywords: const [
                'onboarding',
                'checklist',
                'setup',
                'first sale'
              ],
              onTap: () =>
                  context.push('/owner-welcome', extra: identity.companyName),
            ),
          if ((isLocalWorkspace && isLocalWorkspaceOwner) ||
              (!isLocalWorkspace && isBillingAdmin))
            SettingsEntry(
              id: 'logo',
              icon: Icons.image_rounded,
              title: 'Business logo',
              subtitle: isLocalWorkspace
                  ? 'Choose the logo saved on this device'
                  : 'Change the logo for your shop',
              keywords: const ['picture', 'brand', 'photo'],
              onTap: () => _showLogoDialog(context, ref),
            ),
          if (!isLocalWorkspace &&
              (perms.canManageBranches ||
                  perms.canUpdateBranches ||
                  perms.canDeleteBranches))
            SettingsEntry(
              id: 'branches',
              icon: Icons.store_rounded,
              title: 'Branches',
              subtitle: 'Add or edit your shop locations',
              keywords: const ['shop', 'location', 'store'],
              onTap: () => _showBranchManagement(
                context,
                canCreate: perms.canManageBranches,
                canUpdate: perms.canUpdateBranches,
                canDelete: perms.canDeleteBranches,
              ),
            ),
          if (!isLocalWorkspace && perms.canUpdateBranches)
            SettingsEntry(
              id: 'hours',
              icon: Icons.schedule_rounded,
              title: 'Opening hours',
              subtitle: 'Choose when each branch opens and closes',
              keywords: const ['open', 'close', 'time', 'days'],
              onTap: () => context.push('/settings/operating-hours'),
            ),
          if ((isLocalWorkspace && isLocalWorkspaceOwner) ||
              (!isLocalWorkspace && isBillingAdmin))
            SettingsEntry(
              id: 'tax',
              icon: Icons.percent_rounded,
              title: 'Tax & receipts',
              subtitle: taxSubtitle,
              keywords: const ['vat', 'tax rate', 'receipt'],
              onTap: () => _showTaxRateDialog(context, ref),
            ),
        ],
      ),
      SettingsSection(
        id: 'team',
        title: 'Team',
        entries: [
          if ((!isLocalWorkspace && perms.canManageUsers) ||
              (isLocalWorkspace && isLocalWorkspaceOwner))
            SettingsEntry(
              id: 'staff',
              icon: Icons.people_rounded,
              title:
                  isLocalWorkspace ? 'Staff on this device' : 'Staff & roles',
              subtitle: isLocalWorkspace
                  ? 'Create local staff profiles with individual PINs and access'
                  : 'Add your team and choose what each person can do',
              keywords: const [
                'users',
                'permissions',
                'cashier',
                'manager',
                'access',
              ],
              onTap: () => context.push('/users'),
            ),
        ],
      ),
      SettingsSection(
        id: 'money',
        title: 'Money & plan',
        entries: [
          if (!isLocalWorkspace && perms.canManageMerchantPayout)
            SettingsEntry(
              id: 'merchant-payouts',
              icon: Icons.account_balance_rounded,
              title: 'Customer payments & payouts',
              subtitle:
                  'Manage the bank account for sales and debt collections',
              keywords: const [
                'bank',
                'payout',
                'settlement',
                'paystack',
                'mpesa'
              ],
              onTap: () => context.push('/payments/setup'),
            ),
          if (!isLocalWorkspace && isBillingAdmin)
            SettingsEntry(
              id: 'billing',
              icon: Icons.workspace_premium_rounded,
              title: 'Plan & billing',
              subtitle: 'Your plan, renewal date, M-Pesa payments and invoices',
              keywords: const ['subscription', 'pay', 'mpesa', 'invoice'],
              onTap: () => context.push('/billing'),
            ),
        ],
      ),
      SettingsSection(
        id: 'devices',
        title: 'Devices & printing',
        entries: [
          SettingsEntry(
            id: 'local-data',
            icon: Icons.storage_rounded,
            title: 'Local data',
            subtitle: 'See where this device keeps shop records',
            keywords: const ['sync', 'backup', 'offline', 'storage', 'data'],
            onTap: () => _showLocalDataSettings(context, ref),
            tileBuilder: (context, entry) => SettingsTile(
              key: const ValueKey('settings-tile-local-data'),
              icon: entry.icon,
              title: entry.title,
              subtitle: 'Encrypted on this device',
              trailing: const SettingsStatusChip(
                  text: 'Local', color: DesignColors.info),
              onTap: entry.onTap,
            ),
          ),
          if (perms.canConfigurePrinter)
            SettingsEntry(
              id: 'printers',
              icon: Icons.print_rounded,
              title: 'Receipts & printers',
              subtitle:
                  'Connect a Bluetooth printer and set how receipts print',
              keywords: const ['printer', 'bluetooth', 'paper', 'print'],
              onTap: () => _showPrinterSettings(context),
            ),
          if (!isLocalWorkspace)
            SettingsEntry(
              id: 'notification-centre',
              icon: Icons.inbox_rounded,
              title: 'Inbox',
              subtitle: 'Everything the app has told you, in one place',
              keywords: const ['inbox', 'messages', 'alerts', 'history'],
              onTap: () => context.push('/notifications'),
            ),
          if (perms.canConfigureNotifications)
            SettingsEntry(
              id: 'notifications',
              icon: Icons.notifications_rounded,
              title: 'Alert settings',
              subtitle: 'Choose which alerts you get on this phone',
              keywords: const ['alerts', 'sound', 'push'],
              onTap: () => _showNotificationSettings(context),
            ),
          if (perms.canSeeAppearance)
            SettingsEntry(
              id: 'appearance',
              icon: Icons.palette_rounded,
              title: 'Appearance',
              subtitle:
                  'Light or dark look; Counterbase updates its icon automatically',
              keywords: const ['theme', 'dark mode', 'light mode', 'colour'],
              trailing: SettingsStatusChip(
                text: themeLabel,
                color: DesignColors.textTertiary,
                showDot: false,
              ),
              onTap: () => _showAppearanceSettings(context),
            ),
        ],
      ),
      SettingsSection(
        id: 'security',
        title: 'Security',
        entries: [
          SettingsEntry(
            id: 'pin',
            icon: Icons.lock_rounded,
            title: isLocalWorkspace && user?['isLocalStaff'] == true
                ? 'Your staff PIN'
                : isLocalWorkspace
                    ? 'Workspace owner PIN'
                    : 'Quick-unlock PIN',
            subtitle: isLocalWorkspace && user?['isLocalStaff'] == true
                ? 'Change the PIN you use to sign in to this staff profile'
                : isLocalWorkspace
                    ? 'Change the PIN that opens this local workspace on this device'
                    : 'A 4–6 digit PIN to open the app on this phone',
            keywords: const ['password', 'pin', 'unlock', 'change pin'],
            onTap: () => _showChangePinDialog(context),
          ),
          if (!isLocalWorkspace || isLocalWorkspaceOwner)
            SettingsEntry(
              id: 'device-security',
              icon: Icons.fingerprint_rounded,
              title: 'Sign-in & auto-lock',
              subtitle: isLocalWorkspace &&
                      getIt<AuthService>().hasActiveLocalStaff
                  ? 'Staff use individual PINs; choose when this register locks'
                  : 'Choose PIN or biometric unlock and when the app locks',
              keywords: const ['biometric', 'face', 'lock', 'security'],
              onTap: () => _showSecuritySettings(context),
            ),
          if (isLocalWorkspace && isLocalWorkspaceOwner)
            SettingsEntry(
              id: 'axon-gateway-key',
              icon: Icons.hub_rounded,
              title: 'Axon AI Gateway key',
              subtitle: 'Store the owner-issued key securely on this device',
              keywords: const ['axon', 'gateway', 'ai key', 'api key'],
              onTap: () => context.push('/settings/ai-gateway'),
            ),
          if (!isLocalWorkspace)
            SettingsEntry(
              id: 'offline-pin',
              icon: Icons.wifi_off_rounded,
              title: 'Offline login PIN',
              subtitle:
                  'Sign in on the shop\'s offline server phone, even with no internet',
              keywords: const ['local server', 'offline', 'hub', 'no internet'],
              onTap: () => _showOfflineAccessPinDialog(context),
            ),
          SettingsEntry(
            id: 'desktop-approvals',
            icon: Icons.laptop_windows_rounded,
            title: 'Desktop sign-ins',
            subtitle: 'Approve computers that ask to sign in with a QR code',
            keywords: const ['desktop', 'laptop', 'qr', 'approve', 'pair'],
            onTap: () => context.push('/settings/desktop-approvals'),
          ),
        ],
      ),
      SettingsSection(
        id: 'data',
        title: 'Data',
        entries: [
          if (perms.canExportData)
            SettingsEntry(
              id: 'export',
              icon: Icons.download_rounded,
              title: 'Download my data',
              subtitle: 'Save your sales, stock and products as PDF or CSV',
              keywords: const ['export', 'csv', 'pdf', 'report', 'excel'],
              onTap: () => _showDataExport(context, ref),
            ),
          if (!isLocalWorkspace && perms.canSeeAuditTrail)
            SettingsEntry(
              id: 'activity',
              icon: Icons.history_rounded,
              title: 'Activity history',
              subtitle: 'See who did what in your shop',
              keywords: const ['audit', 'log', 'trail', 'changes'],
              onTap: () => _showAuditTrail(context),
            ),
        ],
      ),
      SettingsSection(
        id: 'help',
        title: 'Help & about',
        entries: [
          SettingsEntry(
            id: 'help',
            icon: Icons.help_rounded,
            title: 'Help & support',
            subtitle: 'Contact us, common questions and guides',
            keywords: const ['faq', 'guide', 'contact', 'call', 'email'],
            onTap: () => _showHelpSupport(context),
          ),
          if (!isLocalWorkspace)
            SettingsEntry(
              id: 'report',
              icon: Icons.bug_report_rounded,
              title: 'Report a problem',
              subtitle: 'Tell us if something is not working',
              keywords: const ['bug', 'issue', 'error', 'feedback'],
              onTap: () => context.push('/settings/report-bug'),
            ),
          SettingsEntry(
            id: 'legal',
            icon: Icons.policy_outlined,
            title: 'Legal & policies',
            subtitle: 'Terms, privacy, billing, and payment policies',
            keywords: const [
              'terms',
              'privacy',
              'policy',
              'billing',
              'payments'
            ],
            onTap: () => context.push('/legal'),
          ),
          SettingsEntry(
            id: 'updates',
            icon: Icons.system_update_rounded,
            title: 'Check for updates',
            subtitle: 'See if a newer version is available',
            keywords: const ['upgrade', 'version', 'new'],
            onTap: () => _checkForUpdates(context),
          ),
          SettingsEntry(
            id: 'about',
            icon: Icons.info_rounded,
            title: 'About Counterbase',
            subtitle: 'Version and company information',
            keywords: const ['version', 'build'],
            onTap: () => _showAboutInfo(context),
            tileBuilder: (context, entry) => FutureBuilder<PackageInfo>(
              future: _settingsPackageInfo,
              builder: (context, snapshot) {
                final info = snapshot.data;
                final subtitle =
                    snapshot.connectionState == ConnectionState.waiting
                        ? 'Loading version…'
                        : snapshot.hasError || info == null
                            ? 'Version unavailable'
                            : 'Version ${info.version}';
                return SettingsTile(
                  key: const ValueKey('settings-tile-about'),
                  icon: entry.icon,
                  title: entry.title,
                  subtitle: subtitle,
                  onTap: entry.onTap,
                );
              },
            ),
          ),
        ],
      ),
      SettingsSection(
        id: 'sign-out',
        title: 'Sign out',
        entries: [
          SettingsEntry(
            id: 'logout',
            icon: Icons.logout_rounded,
            title: 'Sign out of this phone',
            subtitle: 'Anything not yet backed up stays safe on this phone',
            keywords: const ['log out', 'logout', 'exit'],
            destructive: true,
            onTap: () => _showLogoutDialog(context, ref),
          ),
          if (!isLocalWorkspace)
            SettingsEntry(
              id: 'logout-all',
              icon: Icons.devices_rounded,
              title: 'Sign out of all devices',
              subtitle: 'Signs you out on every phone and browser',
              keywords: const ['log out', 'logout everywhere'],
              destructive: true,
              onTap: () => _showLogoutDialog(context, ref, allDevices: true),
            ),
        ],
      ),
    ];

    return Scaffold(
      appBar: BrandedAppBar(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/settings', 'Settings'),
        showBackButton: false,
      ),
      body: SettingsSectionList(
        header: SettingsProfileHeader(
          name: (user?['name'] ?? user?['email'] ?? 'User').toString(),
          email: (user?['email'] ?? '').toString(),
          roleLabel: _roleLabel(user?['role']),
          businessName: identity.companyName,
          // A local workspace has no invite or synchronization code. Its
          // tenant slug is only a device-local identifier, so don't present it
          // as something another shop should copy to join.
          companyCode: isLocalWorkspace ? '' : _companyCodeFor(user),
          branchName: identity.branchName,
          isOnline: isOnline,
          isLocalWorkspace: isLocalWorkspace,
        ),
        sections: sections,
        footer: const _SettingsFooter(),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref,
      {bool allDevices = false}) async {
    // Capture the settings screen context BEFORE the async gap, since the
    // dialog's own context is disposed as soon as it closes.
    final settingsContext = context;

    final confirmed = await showConfirmDialog(
      context,
      title: allDevices ? 'Sign out of all devices' : 'Sign out',
      message: allDevices
          ? 'This signs you out on every phone and browser. Anything not yet backed up stays saved on this phone.'
          : 'Sign out of this phone? Anything not yet backed up stays saved on this phone.',
      confirmLabel: allDevices ? 'Sign out everywhere' : 'Sign out',
      confirmColor: DesignColors.error,
    );
    if (!confirmed) return;

    await ref
        .read(authControllerProvider.notifier)
        .logout(allDevices: allDevices);
    if (settingsContext.mounted) {
      settingsContext.go('/login');
    }
  }

  // ===== LOCAL DATA SETTINGS =====
  void _showLocalDataSettings(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final auth = getIt<AuthService>();
    final localWorkspace = auth.isLocalWorkspace;
    final canManageLocalData = auth.isLocalWorkspaceOwner;
    showModalBottomSheet(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: SingleChildScrollView(
            child: SettingsSheetScaffold(
              title: 'Local data',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GroupedCard(
                    margin: EdgeInsets.zero,
                    children: [
                      _InfoRow('Shop records', 'Stored on this device'),
                      _InfoRow('Database', 'Encrypted'),
                      _InfoRow('Cloud sync', 'Not connected'),
                    ],
                  ),
                  if (localWorkspace && canManageLocalData) ...[
                    const SizedBox(height: DesignSpacing.lg),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _createLocalPortableBackup(pageContext);
                      },
                      icon: const Icon(Icons.enhanced_encryption_rounded),
                      label: const Text('Create encrypted device backup'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: DesignColors.brand,
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _restoreLocalPortableBackup(pageContext, ref);
                      },
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore encrypted device backup'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const Text(
                      'A password-protected .cbmobile file copies shop records, product photos, the shop logo, and scanned supplier receipts to another Counterbase phone; it does not sync. Photos are limited to 16 MB each and 128 MB total. Set a new PIN and add the Axon Gateway key on the receiving phone.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _createLocalArchiveTransfer(pageContext);
                      },
                      icon: const Icon(Icons.devices_rounded),
                      label: const Text('Create cross-platform transfer'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const Text(
                      'Encrypted .cbarchive transfers move products, customers, completed sales with line discounts, and current stock. Balanced cash/credit split details stay in the archive, but customer balances and collections are not transferred. Supplier finance, photos, held carts, and device settings are also excluded; use the full .cbmobile backup for a complete phone-to-phone copy.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _restoreLocalArchive(pageContext, ref);
                      },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Import shop transfer or archive'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    const Text(
                      'Import an encrypted .cbarchive transfer or a shop archive prepared during migration.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        GoRouter.of(pageContext)
                            .push('/settings/archive-history');
                      },
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Browse imported archive history'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ] else if (localWorkspace) ...[
                    const SizedBox(height: DesignSpacing.md),
                    const Text(
                      'Only the workspace owner can create, restore, or import shop backups on this device.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                  ] else ...[
                    const SizedBox(height: DesignSpacing.md),
                    const Text(
                      'Unlock the local shop to create or restore an encrypted device backup.',
                      style: TextStyle(color: DesignColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: DesignSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  LocalPortableBackupService _localPortableBackupService() =>
      LocalPortableBackupService(
        database: getIt<AppDatabase>(),
        storage: getIt<StorageService>(),
        auth: getIt<AuthService>(),
      );

  Future<void> _createLocalPortableBackup(BuildContext context) async {
    final passphrase = await _requestNewPortableBackupPassphrase(context);
    if (passphrase == null || !context.mounted) return;
    _showLocalDataProgress(context, 'Preparing encrypted shop backup…');
    var progressOpen = true;
    try {
      final service = _localPortableBackupService();
      final file = await service.createBackup(passphrase: passphrase);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
      await service.shareBackup(file);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Encrypted backup ready. Referenced catalog photos, shop logo, and supplier receipts are included. Save a copy and keep its password separately.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      if (progressOpen) Navigator.of(context, rootNavigator: true).pop();
      _showLocalDataError(context, error);
    }
  }

  Future<void> _createLocalArchiveTransfer(BuildContext context) async {
    final passphrase = await _requestNewPortableBackupPassphrase(context);
    if (passphrase == null || !context.mounted) return;
    _showLocalDataProgress(context, 'Preparing cross-platform transfer…');
    var progressOpen = true;
    try {
      final service = LocalArchiveExportService(
        database: getIt<AppDatabase>(),
        storage: getIt<StorageService>(),
        auth: getIt<AuthService>(),
      );
      final file = await service.createArchive(passphrase: passphrase);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
      await service.shareArchive(file);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Verified encrypted transfer ready. It includes customer balances, collection history, payment schedules, products, completed sales, and stock. Keep the password separate from the file.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      if (progressOpen) Navigator.of(context, rootNavigator: true).pop();
      _showLocalDataError(context, error);
    }
  }

  Future<void> _restoreLocalPortableBackup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = _localPortableBackupService();
    MobilePortableBackupPreview? preview;
    try {
      preview = await service.pickAndInspect(
        requestPassphrase: () => _requestPortableBackupPassphrase(context),
      );
    } catch (error) {
      if (context.mounted) _showLocalDataError(context, error);
      return;
    }
    if (preview == null || !context.mounted) return;
    final selectedPreview = preview;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Replace this phone with ${selectedPreview.tenantName}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup for ${selectedPreview.ownerName.isEmpty ? 'the shop owner' : selectedPreview.ownerName}, created ${MaterialLocalizations.of(dialogContext).formatMediumDate(selectedPreview.createdAt.toLocal())}. It contains ${selectedPreview.products} products, ${selectedPreview.customers} customers, ${selectedPreview.sales} sales, ${selectedPreview.branches} branches and ${selectedPreview.images} photos.',
              ),
              const SizedBox(height: DesignSpacing.md),
              const Text(
                'Continuing replaces all shop records on this phone. Included photos are copied to this phone. Its PIN and Axon Gateway key stay here.',
              ),
              const SizedBox(height: DesignSpacing.md),
              const Text(
                'Only continue if you recognize this shop and have another copy of any data you need to keep.',
                style: TextStyle(color: DesignColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Replace shop records'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    _showLocalDataProgress(context, 'Restoring encrypted shop records…');
    var progressOpen = true;
    try {
      await service.restoreBackup(preview: selectedPreview);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
      ref.read(authControllerProvider.notifier).refreshFromService();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${preview.tenantName}: ${preview.products} products, ${preview.customers} customers, ${preview.sales} sales and ${preview.images} photos.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      if (progressOpen) Navigator.of(context, rootNavigator: true).pop();
      _showLocalDataError(context, error);
    }
  }

  void _showLocalDataProgress(BuildContext context, String label) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: DesignSpacing.md),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }

  void _showLocalDataError(BuildContext context, Object error) {
    final String? safeMessage = switch (error) {
      FormatException exception => exception.message,
      StateError exception => exception.message.toString(),
      FileSystemException exception => exception.message,
      _ => null,
    };
    final message = safeMessage?.trim() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.isEmpty
            ? 'Counterbase could not complete that backup action. Try again.'
            : message),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<String?> _requestNewPortableBackupPassphrase(
    BuildContext context,
  ) {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            if (password.text.length < 12 || password.text.contains('\u0000')) {
              setDialogState(
                () => errorText = 'Use at least 12 characters.',
              );
              return;
            }
            if (password.text != confirmation.text) {
              setDialogState(() => errorText = 'The passwords do not match.');
              return;
            }
            Navigator.of(dialogContext).pop(password.text);
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Protect your shop backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a password with at least 12 characters. You will need it to restore the backup. Counterbase cannot recover a forgotten password.',
                ),
                const SizedBox(height: DesignSpacing.md),
                TextField(
                  controller: password,
                  autofocus: true,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Backup password',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: DesignSpacing.sm),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  maxLength: 1024,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: errorText.isEmpty ? null : errorText,
                    counterText: '',
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Create backup'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      password.dispose();
      confirmation.dispose();
    });
  }

  Future<String?> _requestPortableBackupPassphrase(BuildContext context) {
    final password = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void submit() {
            if (password.text.length < 12 || password.text.contains('\u0000')) {
              setDialogState(
                () => errorText = 'Use at least 12 characters.',
              );
              return;
            }
            Navigator.of(dialogContext).pop(password.text);
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('Unlock encrypted backup'),
            content: TextField(
              controller: password,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 1024,
              decoration: InputDecoration(
                labelText: 'Backup password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                errorText: errorText.isEmpty ? null : errorText,
                counterText: '',
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Unlock backup'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(password.dispose);
  }

  Future<void> _restoreLocalArchive(BuildContext context, WidgetRef ref) async {
    final archiveService = LocalArchiveImportService(
      database: getIt<AppDatabase>(),
      storage: getIt<StorageService>(),
      auth: getIt<AuthService>(),
    );
    LocalArchiveImportPreview? preview;
    try {
      preview = await archiveService.pickArchive(
        requestPassphrase: () => _requestArchivePassphrase(context),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }
    if (preview == null || !context.mounted) return;
    final selectedPreview = preview;
    final customerCreditNotes = <String>[
      if (selectedPreview.customerBalanceCount > 0)
        'Current balances for ${selectedPreview.customerBalanceCount} customers will be restored to their accounts.',
      if (selectedPreview.customerInstallmentCount > 0)
        '${selectedPreview.customerInstallmentCount} scheduled customer payments will be restored.',
      if (selectedPreview.customerCreditEntryCount > 0)
        '${selectedPreview.customerCreditEntryCount} original online credit entries remain read-only in archive history; their open amounts are included in customer balances and are not recreated as separate debts.',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore ${selectedPreview.tenantName}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedPreview.workspaceMatches
                    ? 'This archive matches the shop open on this device. It contains ${selectedPreview.branchCount} branches, ${selectedPreview.productCount} products, ${selectedPreview.customerCount} customers, ${selectedPreview.saleCount} sales, ${selectedPreview.supplierCount} suppliers, ${selectedPreview.supplierInvoiceCount} supplier invoices and ${selectedPreview.customerCollectionCount} customer collections.'
                    : 'This archive contains ${selectedPreview.branchCount} branches, ${selectedPreview.productCount} products, ${selectedPreview.customerCount} customers, ${selectedPreview.saleCount} sales, ${selectedPreview.supplierCount} suppliers, ${selectedPreview.supplierInvoiceCount} supplier invoices and ${selectedPreview.customerCollectionCount} customer collections. It will name this empty local workspace ${selectedPreview.tenantName}. If the device already has shop data, the restore will stop without changing it.',
              ),
              if (customerCreditNotes.isNotEmpty) ...[
                const SizedBox(height: DesignSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: DesignColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                      color: DesignColors.warning.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    customerCreditNotes.join(' '),
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
              ],
              if (!selectedPreview.workspaceMatches) ...[
                const SizedBox(height: DesignSpacing.md),
                const Text(
                  'Staff profiles already on this device keep their PINs, roles and active status. They will be assigned to this shop’s selected branch. Staff profiles and PINs from the archive are not recreated.',
                ),
              ],
              if (selectedPreview.preservedOnlyDescriptions.isNotEmpty) ...[
                const SizedBox(height: DesignSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: DesignColors.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                      color: DesignColors.warning.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.archive_outlined,
                              size: 18, color: DesignColors.warning),
                          SizedBox(width: DesignSpacing.xs),
                          Expanded(
                            child: Text(
                              'Kept in backup, not restored to app screens',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: DesignSpacing.xs),
                      Text(
                        selectedPreview.preservedOnlyDescriptions
                            .map((section) => '• $section')
                            .join('\n'),
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DesignSpacing.md),
              const Text(
                'The transfer file is password-encrypted. Existing records with matching IDs are kept, and the restore commits in one transaction. The imported archive is saved inside this device’s encrypted database. Old passwords, PINs, login tokens and payment-provider responses are excluded.',
              ),
              const SizedBox(height: DesignSpacing.md),
              Text(
                'Prepared ${MaterialLocalizations.of(dialogContext).formatMediumDate(selectedPreview.createdAt.toLocal())}.',
                style: const TextStyle(color: DesignColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(selectedPreview.workspaceMatches
                ? 'Restore supported records'
                : 'Set up with supported records'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: DesignSpacing.md),
            Expanded(child: Text('Restoring shop records…')),
          ],
        ),
      ),
    );
    try {
      final result = await archiveService.importArchive(selectedPreview);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ref.read(authControllerProvider.notifier).refreshFromService();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.alreadyImported
              ? 'This archive was already restored. No duplicate records were added.'
              : 'Archive restored for ${result.tenantName}. Supported shop, sales, supplier invoice and linked customer collection records are available offline. Keep the encrypted archive for history this edition does not yet display.'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<String?> _requestArchivePassphrase(BuildContext context) {
    final controller = TextEditingController();
    var errorText = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          scrollable: true,
          title: const Text('Unlock shop archive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Enter the password used when this archive was prepared.'),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Archive password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                onSubmitted: (_) {
                  if (controller.text.length < 12) {
                    setDialogState(
                        () => errorText = 'Use at least 12 characters.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(controller.text);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.length < 12) {
                  setDialogState(
                      () => errorText = 'Use at least 12 characters.');
                  return;
                }
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('Unlock archive'),
            ),
          ],
        ),
      ),
    ).whenComplete(controller.dispose);
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
      useRootNavigator: true,
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
      useRootNavigator: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _NotificationSettingsSheet(
        notifySales: notifySales,
        notifyInventory: notifyInventory,
        notifySync: notifySync,
        localWorkspace: getIt<AuthService>().isLocalWorkspace,
      ),
    );
  }

  // ===== APPEARANCE SETTINGS =====
  void _showAppearanceSettings(BuildContext context) {
    showModalBottomSheet(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final currentMode = ref.watch(themeModeProvider);
        return SettingsSheetScaffold(
          title: 'Appearance',
          child: Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GroupedCard(
                    margin: EdgeInsets.zero,
                    children: [
                      SettingsRow(
                        icon: Icons.light_mode_rounded,
                        iconColor: currentMode == ThemeMode.light
                            ? DesignColors.accent
                            : null,
                        title: 'Light',
                        showChevron: false,
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
                        title: 'Dark',
                        showChevron: false,
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
                        title: 'Match my phone',
                        showChevron: false,
                        subtitle: "Uses your phone's light or dark setting",
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
                  const SizedBox(height: DesignSpacing.lg),
                  const LivingIconCard(),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ===== QUICK UNLOCK PIN =====
  // In a connected workspace, keep the local unlock PIN aligned with the
  // account PIN. A standalone local workspace has no account server, so its
  // PIN is stored only in this device's secure local storage.
  void _showChangePinDialog(BuildContext context) async {
    final storage = getIt<StorageService>();
    final authService = getIt<AuthService>();
    final isLocalWorkspace = authService.isLocalWorkspace;
    final isLocalStaff =
        isLocalWorkspace && authService.currentUser?['isLocalStaff'] == true;
    final currentUserId = authService.currentUser?['id']?.toString() ?? '';
    final hasExistingPin = isLocalStaff
        ? await storage.hasLocalStaffPin(currentUserId)
        : await storage.hasLocalPinSet();
    final canUseBiometricRecovery = isLocalWorkspace &&
        !isLocalStaff &&
        hasExistingPin &&
        storage.isBiometricEnabled() &&
        await authService.isBiometricAvailable();
    if (!context.mounted) return;

    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;
    bool isSaving = false;
    bool biometricVerified = false;
    bool verifyingBiometric = false;
    final pinFormatters = [FilteringTextInputFormatter.digitsOnly];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => SettingsDialog(
          title: hasExistingPin
              ? isLocalStaff
                  ? 'Change your staff PIN'
                  : 'Change quick-unlock PIN'
              : isLocalStaff
                  ? 'Set your staff PIN'
                  : 'Set quick-unlock PIN',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasExistingPin
                    ? isLocalStaff
                        ? 'Choose 4–6 digits. Enter your current staff PIN first.'
                        : isLocalWorkspace && canUseBiometricRecovery
                            ? 'Choose 4–6 digits. Confirm with your current PIN or your device biometrics.'
                            : 'Choose 4–6 digits. Enter your current PIN first to confirm it is you.'
                    : isLocalWorkspace
                        ? 'Choose 4–6 digits to unlock Counterbase on this phone.'
                        : 'Choose 4–6 digits. You will use this PIN to open the app on this phone and to sign in quickly.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(dialogContext).brightness == Brightness.dark
                              ? DesignColors.darkTextSecondary
                              : DesignColors.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: DesignSpacing.lg),
              if (hasExistingPin) ...[
                TextField(
                  controller: currentPinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: pinFormatters,
                  maxLength: 6,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Current PIN',
                    hintText: '4–6 digits',
                    counterText: '',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: DesignSpacing.md),
              ],
              if (canUseBiometricRecovery) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: isSaving || verifyingBiometric
                        ? null
                        : () async {
                            setDialogState(() {
                              verifyingBiometric = true;
                              error = null;
                            });
                            final verified =
                                await authService.loginWithBiometrics();
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              verifyingBiometric = false;
                              biometricVerified = verified;
                              if (verified) currentPinController.clear();
                              error = verified
                                  ? null
                                  : 'Biometric check was not completed. Try your current PIN instead.';
                            });
                          },
                    icon: verifyingBiometric
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(biometricVerified
                            ? Icons.verified_user_rounded
                            : Icons.fingerprint_rounded),
                    label: Text(biometricVerified
                        ? 'Biometrics verified'
                        : 'Forgot PIN? Verify with biometrics'),
                  ),
                ),
                const SizedBox(height: DesignSpacing.sm),
              ],
              TextField(
                controller: newPinController,
                keyboardType: TextInputType.number,
                inputFormatters: pinFormatters,
                maxLength: 6,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'New PIN',
                  hintText: '4–6 digits',
                  counterText: '',
                  prefixIcon: Icon(Icons.key_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                controller: confirmPinController,
                keyboardType: TextInputType.number,
                inputFormatters: pinFormatters,
                maxLength: 6,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onSubmitted: (_) {},
                decoration: const InputDecoration(
                  labelText: 'Confirm new PIN',
                  hintText: 'Enter it again',
                  counterText: '',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: DesignSpacing.md),
                Text(
                  error!,
                  style: Theme.of(dialogContext)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DesignColors.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              child: const Text('Cancel'),
            ),
            SettingsPrimaryButton(
              label: 'Save PIN',
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : () async {
                      final currentPin = currentPinController.text;
                      final newPin = newPinController.text;
                      final confirmPin = confirmPinController.text;
                      final validPin = RegExp(r'^\d{4,6}$');

                      if (hasExistingPin && !biometricVerified) {
                        if (!validPin.hasMatch(currentPin)) {
                          setDialogState(
                              () => error = 'Enter your current 4–6 digit PIN');
                          return;
                        }
                        final isCorrect = await authService
                            .verifyLocalPinForSensitiveAction(currentPin);
                        if (!isCorrect) {
                          setDialogState(() => error =
                              authService.pinThrottleMessage ??
                                  'That current PIN is not correct');
                          return;
                        }
                      }
                      if (!validPin.hasMatch(newPin)) {
                        setDialogState(() => error =
                            'Your PIN must be 4–6 digits, numbers only');
                        return;
                      }
                      if (newPin != confirmPin) {
                        setDialogState(
                            () => error = 'The two PINs do not match');
                        return;
                      }

                      setDialogState(() {
                        isSaving = true;
                        error = null;
                      });
                      try {
                        // Keep connected account credentials in sync. Local
                        // workspaces have no account API by design.
                        if (!isLocalWorkspace) {
                          await getIt<ApiClient>().setPin(newPin);
                        }
                        if (isLocalStaff) {
                          await authService.setCurrentLocalStaffPin(newPin);
                        } else {
                          await authService.setLocalPin(newPin);
                        }
                        if (!context.mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _showSnack(
                          context,
                          isLocalStaff
                              ? 'Staff PIN updated'
                              : 'Quick-unlock PIN updated',
                        );
                      } on DioException catch (e) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                          error = e.response?.statusCode == 404
                              ? 'Connect to the internet before changing your PIN. It cannot be changed while using the offline server phone.'
                              : 'Could not update your PIN. Check your connection and try again.';
                        });
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSaving = false;
                          error =
                              'Could not update your PIN. Please try again.';
                        });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ===== OFFLINE ACCESS PIN =====
  // Authorizes this account to log into ANY phone acting as a local
  // server (the shop's offline server phone) with no internet connection.
  // Distinct from _showChangePinDialog's quick-unlock PIN, which only
  // unlocks an already-authenticated session on this specific device.
  void _showOfflineAccessPinDialog(BuildContext context) {
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String? error;
    bool isSaving = false;
    final pinFormatters = [FilteringTextInputFormatter.digitsOnly];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return SettingsDialog(
            title: 'Offline login PIN',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: DesignSpacing.md),
                  child: Text(
                    'Set a PIN so you can sign in as yourself on the shop\'s '
                    'offline server phone, even when there is no internet. '
                    'You must set it now, while you are online.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: pinFormatters,
                  maxLength: 6,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Offline login PIN',
                    hintText: '4–6 digits',
                    counterText: '',
                    prefixIcon: Icon(Icons.wifi_off_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPinController,
                  keyboardType: TextInputType.number,
                  inputFormatters: pinFormatters,
                  maxLength: 6,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Confirm offline login PIN',
                    hintText: 'Enter it again',
                    counterText: '',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DesignColors.error)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
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
                    _showSnack(context, 'Offline login PIN saved');
                  } catch (e) {
                    setDialogState(() {
                      isSaving = false;
                      error =
                          'Could not save. Check your connection and try again.';
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
    final biometricAvailable = await authService.isBiometricAvailable();
    final primaryLoginMethod = storage.getPrimaryLoginMethod();
    final isLocalWorkspace = authService.isLocalWorkspace;
    final hasLocalStaff = authService.hasActiveLocalStaff;

    if (!context.mounted) return;

    showModalBottomSheet(
      useRootNavigator: true,
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
          primaryLoginMethod: primaryLoginMethod,
          isLocalWorkspace: isLocalWorkspace,
          hasLocalStaff: hasLocalStaff,
          scrollController: scrollController,
        ),
      ),
    );
  }

  // ===== HELP & SUPPORT =====
  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SettingsSheetScaffold(
          title: 'Help & support',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsGroupLabel('Contact'),
              GroupedCard(
                children: [
                  SettingsRow(
                    icon: Icons.email_outlined,
                    title: 'Email us',
                    subtitle: 'support@archeaxon.com',
                    onTap: () => _openSupportContact(
                      context,
                      Uri(scheme: 'mailto', path: 'support@archeaxon.com'),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.phone_outlined,
                    title: 'Call us',
                    subtitle: '0742126582',
                    onTap: () => _openSupportContact(
                      context,
                      Uri(scheme: 'tel', path: '0742126582'),
                    ),
                  ),
                ],
              ),
              const SettingsGroupLabel('Guides'),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.quiz_outlined,
                    title: 'Common questions',
                    subtitle: 'Quick answers to what shop owners ask most',
                    onTap: () {
                      Navigator.pop(context);
                      _showFAQ(context);
                    },
                  ),
                  SettingsRow(
                    icon: Icons.description_outlined,
                    title: 'User Guide',
                    subtitle: 'Step-by-step help for using the app',
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

  Future<void> _openSupportContact(BuildContext context, Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }
    showGlassSnackBar(
      context,
      'No app could open this contact. You can use ${uri.path} directly.',
      icon: Icons.info_outline_rounded,
      color: DesignColors.warning,
    );
  }

  void _showFAQ(BuildContext context) {
    final localWorkspace = getIt<AuthService>().isLocalWorkspace;
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        title: 'Common questions',
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Q: How do I add items to the cart?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'A: Tap a product on the POS screen and select the quantity.'),
              const SizedBox(height: 16),
              const Text('Q: How do I manage products?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'A: Go to the Products tab. Use the + button to add products and the categories button to manage categories.'),
              const SizedBox(height: 16),
              const Text('Q: Can I work offline?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(localWorkspace
                  ? 'A: Yes. This local workspace works offline. Sales and shop records stay on this device and do not sync to a cloud account.'
                  : 'A: Yes. Sales and product data are stored locally and sync automatically when you\'re back online.'),
              const SizedBox(height: 16),
              const Text('Q: How do I change my PIN?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('A: Go to Settings > Quick-unlock PIN.'),
              const SizedBox(height: 16),
              const Text('Q: How do I process a refund?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(localWorkspace
                  ? 'A: Open the receipt and void the sale with a reason. Stock is returned. If you physically return till cash, select the cash-refund option so the till is correct. Refund M-Pesa or card payments through the original provider; voiding alone never sends a refund.'
                  : 'A: Open the receipt and void the sale with a reason. Voiding reverses the sale record and stock, but does not send money back. Refund the payment through its original payment method.'),
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
    final info = await _settingsPackageInfo;
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
        final surface =
            isDark ? DesignColors.darkSurfaceElevated : Colors.white;
        // Deliberately a plain Dialog, not Flutter's AboutDialog — that
        // widget always injects a "VIEW LICENSES" button surfacing every
        // open-source package's license text, which is developer-facing
        // noise a customer has no use for and no way to hide.
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusXxl)),
          child: Padding(
            padding: const EdgeInsets.all(DesignSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: DesignColors.brand,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  ),
                  child: const Icon(Icons.storefront,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 16),
                Text('Counterbase',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800, color: titleColor)),
                const SizedBox(height: 4),
                Text(_formatReleaseName(info.version),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: secondaryColor)),
                const SizedBox(height: 16),
                Text(
                  'A complete point-of-sale system for managing sales, inventory, and business operations.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: titleColor, height: 1.4),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Powered by Arche Axon',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: secondaryColor,
                                  fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => launchUrl(
                          Uri.parse('https://archeaxon.com'),
                          mode: LaunchMode.inAppBrowserView,
                        ),
                        child: Text(
                          'archeaxon.com',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: DesignColors.brand,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('© 2026 Arche Axon',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: secondaryColor)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style:
                        TextButton.styleFrom(minimumSize: const Size(64, 48)),
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
      return 'Counterbase $marketingVersion';
    }

    return 'Counterbase $version';
  }

  // ===== ADMIN-ONLY: BRANCH MANAGEMENT =====
  // ===== ADMIN-ONLY: TAX RATE =====
  Future<bool> _cacheTenantUpdate(
    WidgetRef ref,
    Map<String, dynamic> tenantData,
  ) async {
    try {
      await getIt<AuthService>().updateTenantSession(tenantData);
      ref.read(authControllerProvider.notifier).refreshFromService();
      return true;
    } catch (_) {
      // The server update is already committed. Refresh the in-memory tenant
      // even if this device could not persist its local session snapshot.
      ref.read(authControllerProvider.notifier).refreshFromService();
      return false;
    }
  }

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
            title: 'Sales tax',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the VAT (tax) percentage added to every sale. Leave it at 0 if you do not charge tax.',
                  style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
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
                          'Print the tax amount on its own line on receipts',
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
                onPressed:
                    isSaving ? null : () => Navigator.of(dialogContext).pop(),
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
                    final auth = getIt<AuthService>();
                    final Map<String, dynamic> updated;
                    if (auth.isLocalWorkspace) {
                      final tenant = auth.currentUser?['tenant'];
                      final currentTenant = tenant is Map
                          ? Map<String, dynamic>.from(tenant)
                          : <String, dynamic>{};
                      final rawSettings = currentTenant['settings'];
                      final settings = rawSettings is Map
                          ? Map<String, dynamic>.from(rawSettings)
                          : <String, dynamic>{};
                      settings['taxRatePercent'] = rate;
                      settings['showTaxOnReceipt'] = showOnReceipt;
                      updated = {
                        ...currentTenant,
                        'settings': settings,
                      };
                      await auth.updateTenantSession(updated);
                      ref
                          .read(authControllerProvider.notifier)
                          .refreshFromService();
                    } else {
                      updated = await getIt<ApiClient>().updateCurrentTenant(
                        taxRatePercent: rate,
                        showTaxOnReceipt: showOnReceipt,
                      );
                      await _cacheTenantUpdate(ref, {
                        'id': updated['id'],
                        'name': updated['name'],
                        'settings': updated['settings'],
                      });
                    }
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (context.mounted) {
                      showGlassSnackBar(
                        context,
                        rate > 0
                            ? 'Tax rate set to ${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%${auth.isLocalWorkspace ? ' on this device' : ''}'
                            : auth.isLocalWorkspace
                                ? 'Tax removed on this device'
                                : 'Tax removed — sales will not be taxed',
                        icon: Icons.check_circle_rounded,
                        color: DesignColors.success,
                      );
                    }
                  } catch (exception) {
                    setDialogState(() {
                      isSaving = false;
                      error = getIt<AuthService>().isLocalWorkspace
                          ? 'Could not save tax settings on this device. Please try again.'
                          : 'Could not save. ${apiErrorMessage(exception)}';
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

  /// Update the tenant's logo. Standalone workspaces keep it in app storage;
  /// connected workspaces use the configured upload service.
  void _showLogoDialog(BuildContext context, WidgetRef ref) {
    final authService = getIt<AuthService>();
    final isLocalWorkspace = authService.isLocalWorkspace;
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
            title: 'Business logo',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLocalWorkspace
                      ? 'Choose a logo image. It will stay on this device and appear on receipts and shop screens.'
                      : 'Pick a new logo from your phone, or turn your current one into a sharper, resizable (SVG) logo.',
                  style: Theme.of(dialogContext)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: secondary),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: isSaving ? null : pickLogo,
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  child: Container(
                    padding: const EdgeInsets.all(DesignSpacing.lg),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DesignColors.darkSurfaceElevated
                          : DesignColors.surfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusLg),
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
                                  child:
                                      Image.file(logoFile!, fit: BoxFit.cover),
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
                            logoFile != null
                                ? 'New logo selected'
                                : 'Choose an image',
                            style: Theme.of(dialogContext)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? DesignColors.darkTextPrimary
                                        : DesignColors.textPrimary),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: secondary),
                      ],
                    ),
                  ),
                ),
                if (logoFile != null && !isLocalWorkspace) ...[
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
                  Text(error!,
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DesignColors.error)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.of(dialogContext).pop(),
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
                          if (isLocalWorkspace) {
                            final storedPath =
                                await _storeLocalBusinessLogo(logoFile!);
                            await authService.updateTenantSession({
                              'logo': storedPath,
                              'logoUrl': storedPath,
                              'logoPublicId': null,
                            });
                            ref
                                .read(authControllerProvider.notifier)
                                .refreshFromService();
                          } else {
                            final apiClient = getIt<ApiClient>();
                            final fileName =
                                logoFile!.uri.pathSegments.isNotEmpty
                                    ? logoFile!.uri.pathSegments.last
                                    : 'company-logo.jpg';

                            String? logoUrl;
                            String? logoPublicId;
                            if (vectorize) {
                              final v = await apiClient.vectorizeLogo(
                                filePath: logoFile!.path,
                                fileName: fileName,
                              );
                              logoUrl =
                                  (v['svgUrl'] ?? v['rasterUrl']) as String?;
                              logoPublicId = v['publicId'] as String?;
                            } else {
                              final uploadResult = await apiClient.uploadImage(
                                filePath: logoFile!.path,
                                fileName: fileName,
                                type: 'logo',
                              );
                              logoUrl = uploadResult['url'] as String?;
                              logoPublicId =
                                  uploadResult['publicId'] as String?;
                            }

                            final updated = await apiClient.updateCurrentTenant(
                              logo: logoUrl,
                              logoPublicId: logoPublicId,
                            );
                            await _cacheTenantUpdate(ref, {
                              'id': updated['id'],
                              'name': updated['name'],
                              'logo': updated['logo'],
                              'logoPublicId': updated['logoPublicId'],
                              'settings': updated['settings'],
                            });
                          }

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            showGlassSnackBar(
                              context,
                              isLocalWorkspace
                                  ? 'Business logo saved on this device'
                                  : vectorize
                                      ? 'Logo updated with a crisp SVG version'
                                      : 'Logo updated',
                              icon: Icons.check_circle_rounded,
                              color: DesignColors.success,
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            isSaving = false;
                            error = isLocalWorkspace
                                ? 'Could not save the logo on this device. Check available storage and try again.'
                                : 'Could not save. ${apiErrorMessage(e)}';
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

  Future<String> _storeLocalBusinessLogo(File source) async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(supportDirectory.path, 'Counterbase', 'images', 'logo'),
    );
    await directory.create(recursive: true);

    final extension = p.extension(source.path).toLowerCase();
    final safeExtension =
        const {'.jpg', '.jpeg', '.png', '.webp', '.heic'}.contains(extension)
            ? extension
            : '.jpg';
    final destination = p.join(
      directory.path,
      'business-${DateTime.now().microsecondsSinceEpoch}$safeExtension',
    );
    await source.copy(destination);
    return destination;
  }

  void _showBranchManagement(
    BuildContext context, {
    required bool canCreate,
    required bool canUpdate,
    required bool canDelete,
  }) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => _BranchManagementSheet(
          scrollController: scrollController,
          canCreate: canCreate,
          canUpdate: canUpdate,
          canDelete: canDelete,
        ),
      ),
    );
  }

  // ===== ADMIN-ONLY: DATA EXPORT =====
  void _showDataExport(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SettingsSheetScaffold(
        title: 'Download my data',
        child: GroupedCard(
          margin: EdgeInsets.zero,
          children: [
            SettingsRow(
              icon: Icons.receipt_long_rounded,
              title: 'Sales',
              subtitle: "This month's sales, as PDF or CSV",
              onTap: () async {
                Navigator.pop(context);
                await _exportSalesData(context, ref);
              },
            ),
            SettingsRow(
              icon: Icons.inventory_rounded,
              title: 'Stock levels',
              subtitle: 'What you have in stock, as PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportInventory(context, ref);
              },
            ),
            SettingsRow(
              icon: Icons.category_rounded,
              title: 'Product list',
              subtitle: 'All your products, as PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportProducts(context, ref);
              },
            ),
            SettingsRow(
              icon: Icons.people_alt_rounded,
              title: 'Customer accounts',
              subtitle:
                  'Contact details, balances and credit limits as PDF or CSV',
              onTap: () async {
                Navigator.pop(context);
                await _exportCustomers(context, ref);
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
      title: 'Download sales',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Preparing your sales file...');
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
        final logoBytes = await ExportDocumentService.fetchLogoBytes(
          identity.logoUrl,
          allowNetwork: !getIt<AuthService>().isLocalWorkspace,
        );
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
      if (context.mounted) {
        _showSnack(
            context, 'Could not prepare your file. ${apiErrorMessage(e)}');
      }
    }
  }

  Future<void> _exportInventory(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Download stock levels',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Preparing your stock file...');
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
        final logoBytes = await ExportDocumentService.fetchLogoBytes(
          identity.logoUrl,
          allowNetwork: !getIt<AuthService>().isLocalWorkspace,
        );
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Inventory Export',
          companyName: identity.companyName,
          subtitle: countLabel(data.length, 'item'),
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(
                heading: 'Inventory', headers: headers, rows: rows),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'inventory_export');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(
            context, 'Could not prepare your file. ${apiErrorMessage(e)}');
      }
    }
  }

  Future<void> _exportProducts(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Download product list',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Preparing your product file...');
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
        final logoBytes = await ExportDocumentService.fetchLogoBytes(
          identity.logoUrl,
          allowNetwork: !getIt<AuthService>().isLocalWorkspace,
        );
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Products Export',
          companyName: identity.companyName,
          subtitle: countLabel(products.length, 'product'),
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(heading: 'Products', headers: headers, rows: rows),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'products_export');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(
            context, 'Could not prepare your file. ${apiErrorMessage(e)}');
      }
    }
  }

  Future<void> _exportCustomers(BuildContext context, WidgetRef ref) async {
    final format = await showShareFormatSheet(
      context,
      title: 'Download customer accounts',
      formats: const [ShareFormatOption.pdf, ShareFormatOption.csv],
    );
    if (format == null || !context.mounted) return;

    try {
      _showSnack(context, 'Preparing your customer file...');
      final customers = await getIt<AppDatabase>().getAllCustomers();
      const headers = [
        'Name',
        'Phone',
        'Email',
        'Location',
        'Balance',
        'Credit Limit',
        'Total Purchases',
        'Total Spent',
      ];
      final rows = [
        for (final customer in customers)
          [
            customer['name']?.toString() ?? '',
            customer['phone']?.toString() ?? '',
            customer['email']?.toString() ?? '',
            customer['location']?.toString() ?? '',
            '${customer['balance'] ?? 0}',
            '${customer['creditLimit'] ?? 0}',
            '${customer['totalPurchases'] ?? 0}',
            '${customer['totalSpent'] ?? 0}',
          ],
      ];

      if (!context.mounted) return;
      if (format == ShareFormat.csv) {
        final csv = ExportDocumentService.buildCsv(headers, rows);
        await ExportDocumentService.shareCsv(csv, 'customer_accounts_export');
      } else {
        final identity = ref.read(tenantIdentityProvider);
        final logoBytes = await ExportDocumentService.fetchLogoBytes(
          identity.logoUrl,
          allowNetwork: !getIt<AuthService>().isLocalWorkspace,
        );
        final bytes = await ExportDocumentService.buildPdfReport(
          title: 'Customer Accounts',
          companyName: identity.companyName,
          subtitle: countLabel(customers.length, 'customer account'),
          logoBytes: logoBytes,
          sections: [
            PdfReportSection(
              heading: 'Customers and balances',
              headers: headers,
              rows: rows,
            ),
          ],
        );
        await ExportDocumentService.sharePdf(bytes, 'customer_accounts_export');
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(
            context, 'Could not prepare your file. ${apiErrorMessage(error)}');
      }
    }
  }

  // ===== ADMIN-ONLY: AUDIT TRAIL =====
  void _showAuditTrail(BuildContext context) {
    showModalBottomSheet(
      useRootNavigator: true,
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
            padding: const EdgeInsets.fromLTRB(DesignSpacing.xl,
                DesignSpacing.md, DesignSpacing.xl, DesignSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: border,
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.xs)))),
                const SizedBox(height: 18),
                Text('Activity history',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Recent activity in your shop',
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
                        return const EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Couldn\'t load activity history',
                          subtitle: 'Check your connection and try again.',
                          iconColor: DesignColors.error,
                        );
                      }
                      final items = (snapshot.data?['items'] as List? ?? [])
                          .cast<Map<String, dynamic>>();
                      if (items.isEmpty) {
                        return const EmptyState(
                          icon: Icons.history_rounded,
                          title: 'No activity yet',
                          subtitle:
                              'Actions like logins and branch changes will appear here.',
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
                                                  entry['createdAt'] as String)
                                              .toLocal())
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
        SnackBar(
          content: Text(
            updateService.errorMessage ?? 'You\'re on the latest version! ✅',
          ),
          duration: const Duration(seconds: 2),
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
        showGlassSnackBar(context,
            'Could not update the till printer setting. ${apiErrorMessage(e)}',
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
        showGlassSnackBar(context,
            'No paired Bluetooth devices found — pair your printer in phone Bluetooth settings first',
            icon: Icons.bluetooth_searching_rounded, color: DesignColors.info);
      }
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(
            context, 'Could not scan for printers. ${apiErrorMessage(e)}',
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
        showGlassSnackBar(
            context, 'Could not connect to the printer. ${apiErrorMessage(e)}',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom + DesignSpacing.sm),
        child: SettingsSheetScaffold(
          title: 'Receipts & printers',
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
                  labelText: 'Paper size',
                  prefixIcon: const Icon(Icons.straighten_rounded),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusLg)),
                ),
                items: const [
                  DropdownMenuItem(value: '58mm', child: Text('58mm (Small)')),
                  DropdownMenuItem(
                      value: '80mm', child: Text('80mm (Standard)')),
                ],
                onChanged: (v) => setState(() => _paperWidth = v ?? '58mm'),
              ),
              const SizedBox(height: 14),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.receipt_long_rounded,
                    title: 'Print receipts automatically',
                    subtitle: 'Print a receipt after every sale',
                    trailing: Switch(
                      value: _autoPrint,
                      activeThumbColor: DesignColors.accent,
                      onChanged: (v) => setState(() => _autoPrint = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const SettingsGroupLabel('Shared printer'),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.smartphone_rounded,
                    title: 'This phone is the till printer',
                    subtitle: _printerMacAddress.isEmpty
                        ? 'Connect a printer above first'
                        : 'Other staff phones will send their receipts here to print. '
                            'Turn this on only on the phone connected '
                            'to the till printer.',
                    trailing: _isDesignatedPrinter == null ||
                            _isSavingDesignation
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
                const SettingsGroupLabel('Paired Bluetooth devices'),
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : (device.macAddress == _printerMacAddress
                                    ? const Icon(Icons.check_circle_rounded,
                                        color: DesignColors.success)
                                    : null),
                            onTap:
                                _isConnecting ? null : () => _connectTo(device),
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
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(
                            vertical: DesignSpacing.md),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd)),
                      ),
                      child: _isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Find printers'),
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
                        await prefs.setString(_SettingsKeys.printerMacAddress,
                            _printerMacAddress);
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
      ),
    );
  }
}

// ===== NOTIFICATION SETTINGS SHEET =====
class _NotificationSettingsSheet extends StatefulWidget {
  final bool notifySales;
  final bool notifyInventory;
  final bool notifySync;
  final bool localWorkspace;

  const _NotificationSettingsSheet({
    required this.notifySales,
    required this.notifyInventory,
    required this.notifySync,
    required this.localWorkspace,
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
  bool _osPermissionGranted = false;
  bool _checkingPermission = true;
  AppUpdateInfo? _availableUpdate;

  @override
  void initState() {
    super.initState();
    _notifySales = widget.notifySales;
    _notifyInventory = widget.notifyInventory;
    _notifySync = widget.notifySync;
    _checkPermission();
    _checkForAvailableUpdate();
    getIt<UpdateCheckService>().addListener(_onUpdateServiceChanged);
  }

  @override
  void dispose() {
    getIt<UpdateCheckService>().removeListener(_onUpdateServiceChanged);
    super.dispose();
  }

  void _onUpdateServiceChanged() {
    if (!mounted) return;
    setState(() {
      _availableUpdate = getIt<UpdateCheckService>().optionalUpdate;
    });
  }

  Future<void> _checkPermission() async {
    final granted = await getIt<NotificationService>().hasPermission();
    if (mounted) {
      setState(() {
        _osPermissionGranted = granted;
        _checkingPermission = false;
      });
    }
  }

  void _checkForAvailableUpdate() {
    final service = getIt<UpdateCheckService>();
    _availableUpdate = service.optionalUpdate;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          DesignSpacing.xl,
          DesignSpacing.md,
          DesignSpacing.xl,
          DesignSpacing.xl + MediaQuery.of(context).padding.bottom,
        ),
        child: SettingsSheetScaffold(
          title: 'Notifications',
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── OS Permission Status ──
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: _checkingPermission
                        ? Icons.hourglass_empty_rounded
                        : _osPermissionGranted
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                    iconColor: _checkingPermission
                        ? null
                        : _osPermissionGranted
                            ? DesignColors.success
                            : DesignColors.error,
                    title: 'Phone notifications',
                    subtitle: _checkingPermission
                        ? 'Checking…'
                        : _osPermissionGranted
                            ? widget.localWorkspace
                                ? 'On — Counterbase can show on-device notices'
                                : 'On — you will get shop alerts'
                            : 'Blocked — turn them on in your phone settings',
                    trailing: _checkingPermission
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _osPermissionGranted
                            ? const Icon(Icons.check_circle_rounded,
                                color: DesignColors.success)
                            : const Icon(Icons.warning_rounded,
                                color: DesignColors.error),
                  ),
                  if (!_osPermissionGranted && !_checkingPermission)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, 0,
                          DesignSpacing.lg, DesignSpacing.md),
                      child: SizedBox(
                        width: double.infinity,
                        child: SettingsPrimaryButton(
                          label: 'Turn on notifications',
                          onPressed: () async {
                            final granted = await getIt<NotificationService>()
                                .requestPermission();
                            if (mounted) {
                              setState(() {
                                _osPermissionGranted = granted;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Available Update ──
              if (_availableUpdate != null)
                GroupedCard(
                  margin: EdgeInsets.zero,
                  children: [
                    SettingsRow(
                      icon: Icons.system_update_alt_rounded,
                      iconColor: DesignColors.accent,
                      title: 'Update available',
                      subtitle: '${cleanReleaseName(
                        _availableUpdate!.displayVersion,
                        fallback:
                            'Counterbase ${_availableUpdate!.latestVersion}',
                      )} is ready to install',
                      trailing: SettingsPrimaryButton(
                        label: 'Update',
                        onPressed: () {
                          Navigator.pop(context);
                          getIt<UpdateCheckService>()
                              .showCachedOptionalUpdateDialog(context);
                        },
                      ),
                    ),
                    if (_availableUpdate!.releaseNotes.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, 0,
                            DesignSpacing.lg, DesignSpacing.md),
                        child: Text(
                          _availableUpdate!.releaseNotes.trim(),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: context
                                      .themed(DesignColors.darkTextSecondary),
                                  height: 1.4),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              if (widget.localWorkspace) ...[
                const GroupedCard(
                  margin: EdgeInsets.zero,
                  children: [
                    SettingsRow(
                      icon: Icons.phone_android_rounded,
                      iconColor: DesignColors.info,
                      title: 'Device-only notifications',
                      subtitle:
                          'This edition can show local app notices. Sales, low-stock, and backup alerts are not active in this device-only workspace.',
                    ),
                  ],
                ),
              ] else ...[
                // These category preferences are applied to connected shop
                // alerts. The local-only edition has no event feed behind
                // them, so it explains that limitation instead of offering
                // switches that cannot change behavior.
                GroupedCard(
                  margin: EdgeInsets.zero,
                  children: [
                    SettingsRow(
                      icon: Icons.point_of_sale_rounded,
                      title: 'Sales alerts',
                      subtitle: 'Know when a sale is completed',
                      trailing: Switch(
                        value: _notifySales,
                        activeThumbColor: DesignColors.accent,
                        onChanged: (v) => setState(() => _notifySales = v),
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.inventory_rounded,
                      title: 'Stock alerts',
                      subtitle: 'Low stock and reorder reminders',
                      trailing: Switch(
                        value: _notifyInventory,
                        activeThumbColor: DesignColors.accent,
                        onChanged: (v) => setState(() => _notifyInventory = v),
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.sync_rounded,
                      title: 'Backup alerts',
                      subtitle: 'Know when a backup finishes or fails',
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
                      await prefs.setBool(
                          _SettingsKeys.notifySync, _notifySync);

                      final anyEnabled =
                          _notifySales || _notifyInventory || _notifySync;
                      String? permissionMessage;
                      if (anyEnabled && !_osPermissionGranted) {
                        final granted = await getIt<NotificationService>()
                            .requestPermission();
                        if (!granted) {
                          permissionMessage =
                              'Notifications are blocked in your phone settings — enable them there to receive alerts.';
                        } else if (mounted) {
                          setState(() {
                            _osPermissionGranted = true;
                          });
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
  final String primaryLoginMethod;
  final bool isLocalWorkspace;
  final bool hasLocalStaff;
  final ScrollController scrollController;

  const _SecuritySettingsSheet({
    required this.biometricEnabled,
    required this.biometricAvailable,
    required this.requireUnlockOnResume,
    required this.autoLockMinutes,
    required this.primaryLoginMethod,
    required this.isLocalWorkspace,
    required this.hasLocalStaff,
    required this.scrollController,
  });

  @override
  State<_SecuritySettingsSheet> createState() => _SecuritySettingsSheetState();
}

class _SecuritySettingsSheetState extends State<_SecuritySettingsSheet> {
  late bool _biometricEnabled;
  late bool _requireUnlockOnResume;
  late int _autoLockMinutes;
  late String _primaryLoginMethod;
  bool _isConfirmingBiometric = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _biometricEnabled = widget.biometricEnabled;
    _requireUnlockOnResume = widget.requireUnlockOnResume;
    const supportedLockDelays = {0, 1, 5, 15, 30};
    _autoLockMinutes = supportedLockDelays.contains(widget.autoLockMinutes)
        ? widget.autoLockMinutes
        : 0;
    _primaryLoginMethod = widget.isLocalWorkspace &&
            !{'pin', 'biometric'}.contains(widget.primaryLoginMethod)
        ? 'pin'
        : widget.primaryLoginMethod;
  }

  /// Turning biometric login on/off takes effect immediately (not deferred
  /// to the Save button) because enabling it requires proving — right
  /// then, with a real OS biometric prompt — that this device's
  /// fingerprint/face actually works. There's no way to "preview" that
  /// without invoking it, and deferring would let a user save a setting
  /// that was never actually verified.
  Future<void> _onBiometricToggled(bool enabling) async {
    if (!enabling) {
      final shouldFallbackToPin = _primaryLoginMethod == 'biometric';
      setState(() => _isConfirmingBiometric = true);
      try {
        final storage = getIt<StorageService>();
        if (shouldFallbackToPin) {
          await storage.setPrimaryLoginMethod('pin');
        }
        if (!mounted) return;
        setState(() {
          if (shouldFallbackToPin) _primaryLoginMethod = 'pin';
        });
        await storage.setBiometricEnabled(false);
        if (!mounted) return;
        setState(() {
          _biometricEnabled = false;
          _isConfirmingBiometric = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isConfirmingBiometric = false);
        showGlassSnackBar(
          context,
          'Could not save the biometric setting. ${apiErrorMessage(e)}',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      return;
    }

    setState(() => _isConfirmingBiometric = true);
    try {
      final confirmed = await getIt<AuthService>().confirmBiometricEnrollment();
      await getIt<StorageService>().setBiometricEnabled(confirmed);
      if (!mounted) return;
      setState(() {
        _biometricEnabled = confirmed;
        _isConfirmingBiometric = false;
        if (!confirmed && _primaryLoginMethod == 'biometric') {
          _primaryLoginMethod = 'pin';
        }
      });
      if (!confirmed && _primaryLoginMethod == 'pin') {
        await getIt<StorageService>().setPrimaryLoginMethod('pin');
      }
      if (!confirmed && mounted) {
        showGlassSnackBar(context, 'Fingerprint check failed or was cancelled',
            icon: Icons.fingerprint_rounded, color: DesignColors.error);
      }
    } catch (e) {
      try {
        final storage = getIt<StorageService>();
        await storage.setBiometricEnabled(false);
        if (_primaryLoginMethod == 'biometric') {
          await storage.setPrimaryLoginMethod('pin');
        }
      } catch (_) {
        // Keep the UI fallback even if secure preference storage is failing.
      }
      if (!mounted) return;
      final shouldFallbackToPin = _primaryLoginMethod == 'biometric';
      setState(() {
        _biometricEnabled = false;
        _isConfirmingBiometric = false;
        if (shouldFallbackToPin) _primaryLoginMethod = 'pin';
      });
      if (mounted) {
        showGlassSnackBar(context,
            'Could not check fingerprint or face unlock. ${apiErrorMessage(e)}',
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Padding(
          padding: EdgeInsets.only(
            left: DesignSpacing.xl,
            right: DesignSpacing.xl,
            top: DesignSpacing.md,
            bottom: DesignSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
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
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.xs)))),
              const SizedBox(height: 18),
              Text('Sign-in & auto-lock',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              GroupedCard(
                margin: const EdgeInsets.only(bottom: DesignSpacing.md),
                children: [
                  SettingsRow(
                    icon: Icons.login_rounded,
                    title: widget.isLocalWorkspace
                        ? 'Primary unlock method'
                        : 'Primary sign-in method',
                    subtitle: widget.isLocalWorkspace
                        ? 'Choose how to unlock this device. Your PIN remains available if biometrics cannot be used.'
                        : 'Choosing biometrics also asks you to unlock when you return. Biometrics restore a remembered session; first sign-in still needs an account.',
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _primaryLoginMethod == 'biometric' &&
                                !(_biometricEnabled &&
                                    widget.biometricAvailable)
                            ? 'pin'
                            : _primaryLoginMethod,
                        isDense: true,
                        borderRadius: BorderRadius.circular(16),
                        items: [
                          if (!widget.isLocalWorkspace) ...[
                            const DropdownMenuItem(
                              value: 'email',
                              child: Text('Email'),
                            ),
                            const DropdownMenuItem(
                              value: 'google',
                              child: Text('Google'),
                            ),
                          ],
                          const DropdownMenuItem(
                            value: 'pin',
                            child: Text('PIN'),
                          ),
                          if (widget.biometricAvailable && _biometricEnabled)
                            const DropdownMenuItem(
                              value: 'biometric',
                              child: Text('Biometric'),
                            ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _primaryLoginMethod = value;
                                    if (value == 'biometric' &&
                                        _biometricEnabled &&
                                        widget.biometricAvailable) {
                                      _requireUnlockOnResume = true;
                                    }
                                  });
                                }
                              },
                      ),
                    ),
                    showChevron: false,
                  ),
                ],
              ),
              GroupedCard(
                children: [
                  SettingsRow(
                    icon: Icons.security_rounded,
                    title: 'Fingerprint or face unlock',
                    subtitle: widget.biometricAvailable
                        ? "Use an enrolled fingerprint or face; PIN and pattern are not biometric sign-in."
                        : widget.hasLocalStaff
                            ? 'Off while local staff profiles are active. The device cannot tell Counterbase which enrolled person passed the biometric check, so each staff member signs in with their own PIN.'
                            : 'Set up fingerprint or face recognition in your device settings first.',
                    enabled: widget.biometricAvailable &&
                        !_isConfirmingBiometric &&
                        !_isSaving,
                    trailing: _isConfirmingBiometric
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Switch(
                            value:
                                _biometricEnabled && widget.biometricAvailable,
                            activeThumbColor: DesignColors.accent,
                            onChanged: widget.biometricAvailable
                                ? (_isSaving ? null : _onBiometricToggled)
                                : null,
                          ),
                  ),
                  SettingsRow(
                    icon: Icons.lock_clock_rounded,
                    title: 'Ask to unlock when I come back',
                    subtitle:
                        'Asks for your fingerprint, PIN or pattern after you leave the app',
                    trailing: Switch(
                      value: _requireUnlockOnResume,
                      activeThumbColor: DesignColors.accent,
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _requireUnlockOnResume = v),
                    ),
                  ),
                ],
              ),
              GroupedCard(
                margin: EdgeInsets.zero,
                children: [
                  SettingsRow(
                    icon: Icons.timer_outlined,
                    title: 'Otherwise, lock after',
                    subtitle: _requireUnlockOnResume
                        ? 'Immediate unlock is on. Turn it off to use a timer.'
                        : 'Ask for your PIN or biometrics after this time away.',
                    enabled: !_requireUnlockOnResume,
                    trailing: DropdownButton<int>(
                      value: _requireUnlockOnResume ? -1 : _autoLockMinutes,
                      underline: const SizedBox(),
                      onChanged: !_requireUnlockOnResume && !_isSaving
                          ? (v) {
                              if (v == null) return;
                              setState(() {
                                if (v == -1) {
                                  _requireUnlockOnResume = true;
                                } else {
                                  _requireUnlockOnResume = false;
                                  _autoLockMinutes = v;
                                }
                              });
                            }
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
                  isLoading: _isSaving,
                  onPressed: () async {
                    if (_isSaving) return;
                    setState(() => _isSaving = true);
                    // Biometric is committed immediately by the toggle itself
                    // (it needs a real, just-in-time authenticate() check) —
                    // only the remaining two settings are deferred to Save.
                    final storage = getIt<StorageService>();
                    try {
                      await storage
                          .setRequireUnlockOnResume(_requireUnlockOnResume);
                      await storage.setAutoLockMinutes(_autoLockMinutes);
                      await storage.setPrimaryLoginMethod(
                        _primaryLoginMethod == 'biometric' &&
                                !(_biometricEnabled &&
                                    widget.biometricAvailable)
                            ? 'pin'
                            : _primaryLoginMethod,
                      );
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(context);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Security settings saved'),
                        ),
                      );
                    } catch (error) {
                      if (!mounted) return;
                      setState(() {
                        // A preference write may have failed after an earlier
                        // one succeeded. Reflect what is actually stored so
                        // the visible controls never claim unsaved values.
                        _requireUnlockOnResume =
                            storage.requireUnlockOnResume();
                        _autoLockMinutes = storage.getAutoLockMinutes();
                        _primaryLoginMethod = storage.getPrimaryLoginMethod();
                        _biometricEnabled = storage.isBiometricEnabled();
                        _isSaving = false;
                      });
                      showGlassSnackBar(
                        context,
                        'Could not save security settings. ${apiErrorMessage(error)}',
                        icon: Icons.error_outline_rounded,
                        color: DesignColors.error,
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

// ===== SHARED WIDGETS =====
class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.sm, vertical: DesignSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.readable(color),
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
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.md, vertical: DesignSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: secondaryColor),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(value,
                style: DesignType.numeric(
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
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DesignSpacing.md, vertical: DesignSpacing.md),
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
              borderRadius: BorderRadius.circular(DesignSpacing.radiusSm),
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
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: secondaryColor)),
              ],
            ),
          ),
          Text(time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;

  const _BranchManagementSheet({
    required this.scrollController,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
  });

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
    return apiErrorMessage(error);
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
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DesignColors.error)),
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
                  decoration: const InputDecoration(labelText: 'Branch Name')),
              const SizedBox(height: 12),
              TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Branch Code')),
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
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DesignColors.error)),
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
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(DesignSpacing.xl, DesignSpacing.md,
            DesignSpacing.xl, DesignSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: border,
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.xs)))),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Branches',
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
                              subtitle: widget.canCreate
                                  ? 'Tap "Add Branch" to create your first one'
                                  : 'Ask an admin to add a branch.',
                            )
                          : ListView.builder(
                              controller: widget.scrollController,
                              itemCount: _branches.length,
                              itemBuilder: (context, index) {
                                final branch = _branches[index];
                                final isActive =
                                    branch['isActive'] as bool? ?? true;
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
                                              text: isActive
                                                  ? 'Active'
                                                  : 'Inactive',
                                              color: isActive
                                                  ? DesignColors.success
                                                  : DesignColors.textTertiary),
                                          if (widget.canUpdate ||
                                              widget.canDelete)
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
                                                if (widget.canUpdate)
                                                  const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text('Edit')),
                                                if (widget.canDelete)
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
            if (widget.canCreate)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showAddBranchDialog,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  icon: const Icon(Icons.add_business),
                  label: const Text('Add Branch'),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SettingsFooter extends StatelessWidget {
  const _SettingsFooter();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FutureBuilder<PackageInfo>(
        future: _settingsPackageInfo,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final build = info == null || info.buildNumber.isEmpty
              ? ''
              : ' (build ${info.buildNumber})';
          final label = info == null
              ? 'Counterbase'
              : 'Counterbase  ·  Version ${info.version}$build';
          return Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          );
        },
      ),
    );
  }
}
