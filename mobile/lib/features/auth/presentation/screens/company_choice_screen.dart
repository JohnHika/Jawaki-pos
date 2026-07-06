import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';

/// First-launch screen: choose between registering a new company
/// or signing in to one that already exists on this backend.
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
  bool _showBackendLink = false;

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

  // ── Backend connection dialog ──────────────────────────────────

  Future<void> _showServerUrlDialog() async {
    final storage = getIt<StorageService>();
    final apiClient = getIt<ApiClient>();
    final current = storage.getServerBaseUrl() ?? '';
    final controller = TextEditingController(text: current);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DesignColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Connect to a backend',
          style: TextStyle(color: DesignColors.darkTextPrimary, fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(color: DesignColors.darkTextPrimary),
          decoration: InputDecoration(
            hintText: 'https://your-backend.com/api/v1',
            hintStyle: const TextStyle(color: DesignColors.darkTextTertiary),
            labelText: 'Backend API URL',
            labelStyle: const TextStyle(color: DesignColors.darkTextSecondary),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: DesignColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: DesignColors.brand),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: DesignColors.brand),
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                await storage.setServerBaseUrl(url);
                apiClient.setBaseUrl(url);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                showGlassSnackBar(
                  context,
                  url.isEmpty
                      ? 'Using the default Axon backend'
                      : 'Backend URL saved',
                  icon: Icons.check_circle_rounded,
                  color: DesignColors.success,
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
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.height < 700;

    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: isSmallScreen ? 32 : 48,
              ),
              child: Column(
                children: [
                  SizedBox(height: isSmallScreen ? 16 : 32),

                  // Axon brand mark — long-press reveals backend connection
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: GestureDetector(
                        onLongPress: () =>
                            setState(() => _showBackendLink = true),
                        child: SvgPicture.asset(
                          'assets/images/axon_logo_mark.svg',
                          width: isSmallScreen ? 72 : 88,
                          height: isSmallScreen ? 72 : 88,
                          semanticsLabel: 'Axon POS',
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 20 : 28),

                  // Title
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Text(
                          'Axon POS',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 26 : 32,
                            fontWeight: FontWeight.w800,
                            color: DesignColors.darkTextPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Connect this device to your business',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 15,
                            fontWeight: FontWeight.w400,
                            color: DesignColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 36 : 56),

                  // Choice cards
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        children: [
                          _buildChoiceCard(
                            icon: Icons.add_business_rounded,
                            title: 'Register a new company',
                            subtitle:
                                'First time here — set up your business, admin login, and first branch',
                            isPrimary: true,
                            onTap: () => context.go('/company-setup'),
                          ),
                          const SizedBox(height: 14),
                          _buildChoiceCard(
                            icon: Icons.badge_outlined,
                            title: 'Sign in with a company code',
                            subtitle:
                                'Your business is already set up on another device',
                            isPrimary: false,
                            onTap: () => context.go('/login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 28 : 40),

                  // Backend connection — hidden until the logo is
                  // long-pressed, since switching servers is a setup/support
                  // action almost no one needs on first launch.
                  AnimatedSwitcher(
                    duration: DesignAnimation.fast,
                    child: _showBackendLink
                        ? TextButton.icon(
                            key: const ValueKey('backend-link'),
                            onPressed: _showServerUrlDialog,
                            style: TextButton.styleFrom(
                              foregroundColor: DesignColors.darkTextTertiary,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.dns_outlined, size: 16),
                            label: const Text(
                              'Connect to a different backend',
                              style: TextStyle(fontSize: 13),
                            ),
                          )
                        : const SizedBox(key: ValueKey('backend-link-hidden')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isPrimary
                ? DesignColors.brand.withValues(alpha: 0.12)
                : DesignColors.darkSurfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? DesignColors.brand.withValues(alpha: 0.4)
                  : DesignColors.darkBorder,
              width: isPrimary ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? DesignColors.brand
                      : DesignColors.darkBorder.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: isPrimary ? Colors.white : DesignColors.darkTextPrimary,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DesignColors.darkTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: DesignColors.darkTextSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: DesignColors.darkTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
