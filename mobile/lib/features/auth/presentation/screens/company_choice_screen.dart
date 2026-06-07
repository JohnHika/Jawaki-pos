import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:levisa_adventures_pos/core/di/injection.dart';
import 'package:levisa_adventures_pos/core/network/api_client.dart';
import 'package:levisa_adventures_pos/core/services/storage_service.dart';
import 'package:levisa_adventures_pos/core/theme/design_system.dart';

/// Screen shown on first app launch to let user choose between
/// creating a new company or signing into an existing one.
/// Axon POS - Professional Point of Sale Platform by Arche Axon Intelligence
class CompanyChoiceScreen extends StatefulWidget {
  const CompanyChoiceScreen({super.key});

  @override
  State<CompanyChoiceScreen> createState() => _CompanyChoiceScreenState();
}

class _CompanyChoiceScreenState extends State<CompanyChoiceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: DesignAnimation.normal,
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: DesignAnimation.defaultCurve,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: DesignAnimation.smooth,
    ));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // â”€â”€ Server URL configuration dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _showServerUrlDialog() async {
    final storage = getIt<StorageService>();
    final apiClient = getIt<ApiClient>();
    final current = storage.getServerBaseUrl() ?? '';
    final controller = TextEditingController(text: current);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'https://your-backend.com/api/v1',
            labelText: 'Backend API URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await storage.setServerBaseUrl(url);
                apiClient.setBaseUrl(url);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(url.isEmpty ? 'Using default URL' : 'Server URL updated')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    // Solid dark background instead of gradient
    final bgColor = isDark ? DesignColors.darkBg : const Color(0xFF1A1A2E);
    final textOnBg = Colors.white;
    final subtextOnBg = Colors.white.withValues(alpha: 0.75);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: bgColor,
        child: SafeArea(
          child: Stack(
            children: [
              // Gear icon â€” top right
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                  tooltip: 'Server settings',
                  onPressed: _showServerUrlDialog,
                ),
              ),

              // Main content
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: isSmallScreen ? 32 : 48,
                ),
                child: Column(
                  children: [
                    SizedBox(height: isSmallScreen ? 24 : 48),

                    // App icon placeholder
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Container(
                          width: isSmallScreen ? 80 : 100,
                          height: isSmallScreen ? 80 : 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.store_rounded,
                            size: 50,
                            color: DesignColors.brand,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 20 : 32),

                    // Title
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          Text(
                            'Welcome',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 28 : 36,
                              fontWeight: FontWeight.w700,
                              color: textOnBg,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Set up your point of sale system',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              fontWeight: FontWeight.w400,
                              color: subtextOnBg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 40 : 64),

                    // Choice cards
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          children: [
                            // Create new company card
                            _buildChoiceCard(
                              isDark: isDark,
                              icon: Icons.add_business_rounded,
                              title: 'Create New Company',
                              subtitle:
                                  'Set up a new company account with your business details',
                              isPrimary: true,
                              onTap: () => context.go('/company-setup'),
                            ),
                            const SizedBox(height: 16),

                            // Sign in to existing card
                            _buildChoiceCard(
                              isDark: isDark,
                              icon: Icons.login_rounded,
                              title: 'Sign In to Existing',
                              subtitle:
                                  'Connect to a company that\'s already set up',
                              isPrimary: false,
                              onTap: () => context.go('/login'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 32 : 48),

                    // Footer
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        'Professional Point of Sale System',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.5),
                          letterSpacing: 1.5,
                        ),
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

  Widget _buildChoiceCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isPrimary
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: isPrimary ? 0.3 : 0.15),
              width: isPrimary ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isPrimary ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
