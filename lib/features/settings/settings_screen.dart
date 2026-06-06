import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/store.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Store store;

  const SettingsScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Store info header
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [
                  JawakiTheme.primaryDeepBlue,
                  Color(0xFF1565C0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  store.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (store.address != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    store.address!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Sections
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: JawakiTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // AI Subscription
        Card(
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JawakiTheme.primaryTeal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, color: JawakiTheme.primaryTeal, size: 22),
            ),
            title: const Text('AI Subscription', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(store.aiStatus ?? 'Not active'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Navigate to AI tab
            },
          ),
        ),

        // Store Details
        Card(
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JawakiTheme.primaryDeepBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.store, color: JawakiTheme.primaryDeepBlue, size: 22),
            ),
            title: const Text('Store Details', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${store.id} • ${store.address ?? "No address"}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),

        // Notifications
        const Card(
          child: ListTile(
            leading: Icon(Icons.notifications, color: JawakiTheme.accentOrange),
            title: Text('Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Enabled'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),

        // Payment Settings
        const Card(
          child: ListTile(
            leading: Icon(Icons.payment, color: JawakiTheme.primaryTeal),
            title: Text('Payment Settings', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('M-Pesa, Cash'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),

        // Receipt Settings
        const Card(
          child: ListTile(
            leading: Icon(Icons.receipt_long, color: JawakiTheme.accentGreen),
            title: Text('Receipt Settings', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Default printer, header, footer'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),

        // Users / Staff
        const Card(
          child: ListTile(
            leading: Icon(Icons.people, color: Colors.purple),
            title: Text('Staff Management', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Manage users and permissions'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),

        const SizedBox(height: 12),

        // App Info
        const Text(
          'About',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: JawakiTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline, color: JawakiTheme.textSecondary),
            title: Text('App Version', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('1.0.0'),
          ),
        ),

        const SizedBox(height: 24),

        // Logout
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showLogoutDialog(context),
            icon: const Icon(Icons.logout, color: JawakiTheme.accentRed),
            label: const Text(
              'Logout',
              style: TextStyle(color: JawakiTheme.accentRed),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: JawakiTheme.accentRed),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: JawakiTheme.accentRed,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}
