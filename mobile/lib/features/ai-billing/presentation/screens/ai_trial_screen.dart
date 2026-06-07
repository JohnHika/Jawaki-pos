import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/ai-billing/presentation/services/ai_billing_service.dart';

class AiTrialScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final VoidCallback onTrialStarted;

  const AiTrialScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.onTrialStarted,
  });

  @override
  State<AiTrialScreen> createState() => _AiTrialScreenState();
}

class _AiTrialScreenState extends State<AiTrialScreen> {
  final AiBillingService _billingService = AiBillingService();
  bool _isLoading = false;
  String? _error;

  Future<void> _startTrial() async {
    setState(() => _isLoading = true);
    try {
      await _billingService.startTrial(widget.branchId);
      if (mounted) {
        widget.onTrialStarted();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).cardColor;
    final textPrimary = Theme.of(context).textTheme.headlineSmall?.color;
    final textSecondary = Theme.of(context).textTheme.bodyLarge?.color;
    final hintColor = Theme.of(context).textTheme.labelMedium?.color;

    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.auto_awesome, size: 48, color: primary),
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 24),

                Text(
                  'Levisa AI Assistant',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                Text(
                  'Get instant insights, product recommendations, and business analytics powered by AI.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),
                const SizedBox(height: 32),

                // Features list
                _FeatureTile(
                  icon: Icons.analytics_outlined,
                  title: 'Sales Analytics',
                  subtitle: 'Understand your sales trends',
                  primary: primary,
                ),
                _FeatureTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Inventory Help',
                  subtitle: 'Smart stock recommendations',
                  primary: primary,
                ),
                _FeatureTile(
                  icon: Icons.lightbulb_outlined,
                  title: 'Business Tips',
                  subtitle: 'AI-powered advice for your store',
                  primary: primary,
                ),
                const SizedBox(height: 32),

                // Trial card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.card_giftcard, color: primary, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            '7 Days Free Trial',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'After your trial, subscribe for just 600 KES/month.',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _startTrial,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.rocket_launch),
                          label: Text(_isLoading ? 'Starting...' : 'Start Free Trial'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: 0.3, duration: 500.ms, curve: Curves.easeOut),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Colors.red, fontSize: 13)),
                ],

                const SizedBox(height: 16),
                Text(
                  'No payment required. Cancel anytime.',
                  style: TextStyle(color: hintColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color primary;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = Theme.of(context).textTheme.headlineSmall?.color;
    final textSecondary = Theme.of(context).textTheme.bodyLarge?.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textPrimary)),
                Text(subtitle, style: TextStyle(color: textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideX(begin: -0.2);
  }
}
