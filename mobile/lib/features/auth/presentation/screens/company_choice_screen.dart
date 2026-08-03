import 'dart:math' as math;

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
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _orbitController;
  late final Animation<double> _entryAnimation;
  bool _showBackendLink = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: DesignAnimation.smooth,
    );
    _orbitController = AnimationController(
      duration: const Duration(milliseconds: 14000),
      vsync: this,
    )..repeat();
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

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
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.height < 760;

    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _orbitController,
                  builder: (context, child) => CustomPaint(
                    key: const ValueKey('entry-motion-field'),
                    painter: _MotionFieldPainter(
                      progress: _orbitController.value,
                    ),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                isCompact ? 18 : 28,
                24,
                isCompact ? 24 : 34,
              ),
              child: FadeTransition(
                opacity: _entryAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.035),
                    end: Offset.zero,
                  ).animate(_entryAnimation),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      SizedBox(height: isCompact ? 26 : 38),
                      _buildHero(isCompact),
                      SizedBox(height: isCompact ? 24 : 32),
                      _buildActionCard(
                        index: '01',
                        icon: Icons.add_business_rounded,
                        title: 'Create your workspace',
                        subtitle:
                            'Set up your business and make your first sale.',
                        detail: 'Owner setup · about 2 minutes',
                        isPrimary: true,
                        onTap: () => context.go('/company-setup'),
                      ),
                      const SizedBox(height: 14),
                      _buildActionCard(
                        index: '02',
                        icon: Icons.login_rounded,
                        title: 'Join an existing business',
                        subtitle:
                            'Use your company code to connect this device.',
                        detail: 'Staff access · ready when you are',
                        isPrimary: false,
                        onTap: () => context.push('/login'),
                      ),
                      const SizedBox(height: 26),
                      Center(
                        child: AnimatedSwitcher(
                          duration: DesignAnimation.fast,
                          child: _showBackendLink
                              ? TextButton.icon(
                                  key: const ValueKey('backend-link'),
                                  onPressed: _showServerUrlDialog,
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        DesignColors.darkTextTertiary,
                                  ),
                                  icon:
                                      const Icon(Icons.tune_rounded, size: 16),
                                  label: const Text(
                                    'Connect to a different backend',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                )
                              : const SizedBox(
                                  key: ValueKey('backend-link-hidden'),
                                  height: 28,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'A calm start for busy counters.',
                          style: TextStyle(
                            color: DesignColors.darkTextTertiary,
                            fontSize: 12,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: DesignColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'AXON / START',
              style: DesignType.numeric(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: DesignColors.darkTextSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        Text(
          'DEVICE 01',
          style: DesignType.numeric(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: DesignColors.darkTextTertiary,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildHero(bool isCompact) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onLongPress: () => setState(() => _showBackendLink = true),
            child: AnimatedBuilder(
              animation: _orbitController,
              builder: (context, child) {
                final angle =
                    math.sin(_orbitController.value * math.pi * 2) * 0.025;
                return Transform.rotate(angle: angle, child: child);
              },
              child: Container(
                width: isCompact ? 102 : 122,
                height: isCompact ? 102 : 122,
                padding: const EdgeInsets.all(21),
                decoration: BoxDecoration(
                  color: DesignColors.darkSurface.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: DesignColors.brand.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: DesignColors.brand.withValues(alpha: 0.18),
                      blurRadius: 34,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: SvgPicture.asset(
                  'assets/images/axon_logo_mark.svg',
                  semanticsLabel: 'Axon POS',
                ),
              ),
            ),
          ),
          SizedBox(height: isCompact ? 24 : 30),
          Text(
            'Your business,\nin motion.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DesignColors.darkTextPrimary,
              fontSize: isCompact ? 30 : 34,
              height: 1.04,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 15),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'Connect your counter, your team, and every sale in one calm operating system.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DesignColors.darkTextSecondary,
                fontSize: isCompact ? 13 : 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String index,
    required IconData icon,
    required String title,
    required String subtitle,
    required String detail,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final borderColor = isPrimary
        ? DesignColors.accent.withValues(alpha: 0.72)
        : DesignColors.darkBorder;
    final surfaceColor = isPrimary
        ? DesignColors.accentSubtle.withValues(alpha: 0.86)
        : DesignColors.darkSurface.withValues(alpha: 0.94);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: isPrimary ? 1.4 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? DesignColors.accent
                      : DesignColors.darkSurfaceElevated,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  icon,
                  size: 25,
                  color: isPrimary
                      ? DesignColors.textInverse
                      : DesignColors.darkTextPrimary,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index,
                      style: DesignType.numeric(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isPrimary
                            ? DesignColors.accentLight
                            : DesignColors.darkTextTertiary,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        color: DesignColors.darkTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: DesignColors.darkTextSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      style: TextStyle(
                        color: isPrimary
                            ? DesignColors.accentLight
                            : DesignColors.darkTextTertiary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_outward_rounded,
                size: 21,
                color: isPrimary
                    ? DesignColors.accentLight
                    : DesignColors.darkTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MotionFieldPainter extends CustomPainter {
  const _MotionFieldPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.245);
    final pulse = 1 + math.sin(progress * math.pi * 2) * 0.06;

    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = DesignColors.brand.withValues(alpha: 0.12);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(center, (86 + (i * 36)) * pulse, orbitPaint);
    }

    final nodes = <Offset>[];
    for (var i = 0; i < 7; i++) {
      final angle = (math.pi * 2 * i / 7) + progress * math.pi * 2;
      final radius = 116 + (i.isEven ? 18 : -8);
      nodes.add(
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius));
    }

    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = DesignColors.brand.withValues(alpha: 0.22);
    for (final node in nodes) {
      canvas.drawLine(center, node, linkPaint);
    }

    final nodePaint = Paint()
      ..color = DesignColors.accent.withValues(alpha: 0.66);
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawCircle(nodes[i], i.isEven ? 3.5 : 2.5, nodePaint);
    }
    canvas.drawCircle(
      center,
      4.5 + math.sin(progress * math.pi * 2) * 1.5,
      Paint()..color = DesignColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _MotionFieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
