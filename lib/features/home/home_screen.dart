import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/store.dart';
import '../ai/ai_tab_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../sales/sales_screen.dart';
import '../inventory/inventory_screen.dart';
import '../settings/settings_screen.dart';
import '../auth/login_screen.dart';

class HomeScreen extends StatefulWidget {
  final Store store;

  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 3; // Start on AI tab

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _getAppBar(),
      drawer: _buildDrawer(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget? _getAppBar() {
    if (_currentIndex == 3) return null; // AI tab - no app bar

    final title = _getTitle();
    // For AI tab, no app bar is shown (AiTabScreen handles its own)

    return AppBar(
      title: Text(title),
      actions: [
        if (_currentIndex == 4)
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {},
          ),
      ],
    );
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Sales';
      case 2:
        return 'Inventory';
      case 3:
        return 'AI Assistant';
      case 4:
        return 'Settings';
      default:
        return 'Jawaki Admin';
    }
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return DashboardScreen(
          storeName: widget.store.name,
          aiStatus: widget.store.aiStatus ?? 'not activated',
        );
      case 1:
        return const SalesScreen();
      case 2:
        return const InventoryScreen();
      case 3:
        return const AiTabScreen();
      case 4:
        return SettingsScreen(store: widget.store);
      default:
        return const AiTabScreen();
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  JawakiTheme.primaryDeepBlue,
                  Color(0xFF1565C0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.store.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.store.address != null)
                  Text(
                    widget.store.address!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              setState(() => _currentIndex = 0);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart),
            title: const Text('Sales'),
            onTap: () {
              setState(() => _currentIndex = 1);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory),
            title: const Text('Inventory'),
            onTap: () {
              setState(() => _currentIndex = 2);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: JawakiTheme.primaryTeal),
            title: const Text(
              'AI Assistant',
              style: TextStyle(color: JawakiTheme.primaryTeal),
            ),
            onTap: () {
              setState(() => _currentIndex = 3);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              setState(() => _currentIndex = 4);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: JawakiTheme.accentRed),
            title: const Text(
              'Logout',
              style: TextStyle(color: JawakiTheme.accentRed),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart),
          label: 'Sales',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.inventory),
          label: 'Stock',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.auto_awesome, color: JawakiTheme.primaryTeal),
          label: 'AI',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
