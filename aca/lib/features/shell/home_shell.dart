import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/api_client.dart';
import '../../state/session.dart';
import '../billing/billing_screen.dart';
import '../overview/overview_screen.dart';
import '../security/security_screen.dart';
import '../tenants/tenants_screen.dart';
import 'more_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.permission, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// null = always available.
  final String? permission;
  final WidgetBuilder builder;
}

final List<_Tab> _allTabs = [
  _Tab('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, Perm.dashboardView,
      (_) => const OverviewScreen()),
  _Tab('Clients', Icons.storefront_outlined, Icons.storefront_rounded, Perm.tenantsView,
      (_) => const TenantsScreen()),
  _Tab('Billing', Icons.payments_outlined, Icons.payments_rounded, Perm.billingView,
      (_) => const BillingScreen()),
  _Tab('Security', Icons.shield_outlined, Icons.shield_rounded, Perm.securityView,
      (_) => const SecurityScreen()),
  _Tab('More', Icons.menu_rounded, Icons.menu_open_rounded, null, (_) => const MoreScreen()),
];

/// Bottom-navigation shell. Only the tabs the signed-in role may use are shown,
/// and each tab is built the first time it is opened (so the app doesn't fire
/// every screen's requests at once against a server that may be waking up).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final tabs = _allTabs.where((t) => t.permission == null || session.can(t.permission!)).toList();
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: Column(
        children: [
          WakingBanner(api: context.read<AcaApi>()),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _visited.contains(i) || i == index ? tabs[i].builder(context) : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: tabs.length < 2
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: context.aca.border))),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() {
                  _index = i;
                  _visited.add(i);
                }),
                destinations: [
                  for (final t in tabs)
                    NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
                ],
              ),
            ),
    );
  }
}
