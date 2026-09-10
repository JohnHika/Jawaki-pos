import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:axon_pos/features/ai-billing/presentation/services/ai_billing_service.dart';
import '../../../../core/theme/design_system.dart';

class AiSubscribeScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const AiSubscribeScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<AiSubscribeScreen> createState() => _AiSubscribeScreenState();
}

class _AiSubscribeScreenState extends State<AiSubscribeScreen> {
  final AiBillingService _billingService = AiBillingService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isCardLoading = false;
  bool _isMpesaCodeLoading = false;
  bool _showMpesaFallback = false;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _payWithCard() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email to receive your receipt');
      return;
    }

    setState(() {
      _isCardLoading = true;
      _error = null;
    });

    try {
      final url = await _billingService.initializePaystackPayment(
        widget.branchId,
        email,
      );
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          setState(() {
            _successMessage =
                'Complete the payment in your browser. Your subscription activates automatically once the card is charged, and renews on its own each month.';
          });
        }
      } else {
        if (mounted) setState(() => _error = 'Could not open the payment page');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCardLoading = false);
    }
  }

  Future<void> _submitMpesaCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the M-Pesa confirmation code');
      return;
    }
    if (code.length < 5) {
      setState(() => _error = 'Invalid code. Please check your SMS.');
      return;
    }

    setState(() {
      _isMpesaCodeLoading = true;
      _error = null;
    });
    try {
      final result = await _billingService.submitPayment(widget.branchId, code);
      if (mounted) {
        setState(() => _successMessage = result['message']);
        _codeController.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isMpesaCodeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandedAppBar(title: 'Subscribe to Axon AI', showLogo: false),
      body: SafeArea(
        child: SingleChildScrollView(
          // Keyboard-safe: keep fields above the keyboard.
          padding: EdgeInsets.fromLTRB(
            DesignSpacing.xl,
            DesignSpacing.xl,
            DesignSpacing.xl,
            DesignSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Price
              GlassCard(
                padding: const EdgeInsets.all(DesignSpacing.lg),
                borderRadius: DesignSpacing.radiusMd,
                borderColor: DesignColors.brand.withValues(alpha: 0.25),
                tint: DesignColors.brand.withValues(alpha: 0.08),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monthly Subscription',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: DesignColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Renews automatically every 30 days',
                            style: TextStyle(
                                color: DesignColors.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'KES ${AiBillingService.subscriptionPrice.toStringAsFixed(0)}',
                      style: DesignType.numeric(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: DesignColors.brand,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: DesignSpacing.xxl),

              // Card payment — primary path, auto-renews
              _SectionCard(
                title: 'Pay with Card',
                subtitle:
                    'Recommended — your subscription renews automatically each month, no need to pay again.',
                children: [
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email for receipt',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: DesignSpacing.lg),
                  GradientButton(
                    label: _isCardLoading ? 'Opening...' : 'Subscribe with Card',
                    icon: Icons.credit_card,
                    isLoading: _isCardLoading,
                    onPressed: _isCardLoading ? null : _payWithCard,
                    height: DesignSpacing.xxl + 26,
                    borderRadius: DesignSpacing.radiusMd,
                  ),
                ],
              ),

              const SizedBox(height: DesignSpacing.lg),

              // Success / error messages
              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.lg),
                  decoration: BoxDecoration(
                    color: DesignColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                        color: DesignColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: DesignColors.success),
                      const SizedBox(width: DesignSpacing.md),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: DesignColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
              ],

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.lg),
                  decoration: BoxDecoration(
                    color: DesignColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                    border: Border.all(
                        color: DesignColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: DesignColors.error),
                      const SizedBox(width: DesignSpacing.md),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: DesignColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
              ],

              // M-Pesa fallback, collapsed by default
              TextButton.icon(
                onPressed: () => setState(
                    () => _showMpesaFallback = !_showMpesaFallback),
                style: TextButton.styleFrom(
                  minimumSize: const Size(64, DesignSpacing.xl + 24),
                ),
                icon: Icon(
                  _showMpesaFallback
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: const Text('Prefer to pay with M-Pesa instead?'),
              ),
              if (_showMpesaFallback) ...[
                const SizedBox(height: DesignSpacing.sm),
                _SectionCard(
                  title: 'Pay with M-Pesa',
                  subtitle:
                      'Manual — you\'ll need to submit this M-Pesa code again next month, since M-Pesa can\'t be auto-charged.',
                  children: [
                    _InstructionStep(
                      number: 1,
                      title: 'Send M-Pesa',
                      description:
                          'Send exactly KES ${AiBillingService.subscriptionPrice.toStringAsFixed(0)} to your store\'s M-Pesa number',
                      highlight: '0742126582',
                    ),
                    const _InstructionStep(
                      number: 2,
                      title: 'Enter Code',
                      description: 'Enter the confirmation code from your SMS',
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    _CodeInputField(
                      controller: _codeController,
                      onSubmitted: _submitMpesaCode,
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    // >=44px tap target.
                    SizedBox(
                      width: double.infinity,
                      height: DesignSpacing.xl + 24,
                      child: OutlinedButton(
                        onPressed:
                            _isMpesaCodeLoading ? null : _submitMpesaCode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DesignColors.brand,
                          side: const BorderSide(color: DesignColors.brand),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                          ),
                        ),
                        child: _isMpesaCodeLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DesignColors.brand),
                              )
                            : const Text('Submit Code'),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: DesignSpacing.xxl),

              const Text(
                'By subscribing, you agree to our Terms of Service and Privacy Policy.',
                style: TextStyle(
                  color: DesignColors.textTertiary,
                  fontSize: 12,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _SectionCard({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(DesignSpacing.lg),
      borderRadius: DesignSpacing.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: DesignColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: DesignSpacing.xs),
            Text(
              subtitle!,
              style: const TextStyle(
                  color: DesignColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4),
            ),
          ],
          const SizedBox(height: DesignSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int number;
  final String title;
  final String description;
  final String? highlight;

  const _InstructionStep({
    required this.number,
    required this.title,
    required this.description,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: DesignColors.brand,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: DesignType.numeric(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: DesignSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: DesignColors.textPrimary,
                  ),
                ),
                const SizedBox(height: DesignSpacing.xs),
                Text(
                  description,
                  style: const TextStyle(
                    color: DesignColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (highlight != null) ...[
                  const SizedBox(height: DesignSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignSpacing.md,
                      vertical: DesignSpacing.sm + 2,
                    ),
                    decoration: BoxDecoration(
                      color: DesignColors.brand.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(DesignSpacing.radiusSm),
                      border: Border.all(
                          color: DesignColors.brand.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          highlight!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.brand,
                          ),
                        ),
                        const SizedBox(width: DesignSpacing.sm),
                        const Icon(Icons.copy,
                            size: 16, color: DesignColors.brand),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeInputField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _CodeInputField({
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    const border = BorderSide(color: DesignColors.surfaceBorder);

    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      keyboardType: TextInputType.text,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        hintText: 'Enter M-Pesa code (e.g., QK8W3X)',
        hintStyle: const TextStyle(
            color: DesignColors.textTertiary,
            fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: border,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: border,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
          borderSide: const BorderSide(color: DesignColors.brand, width: 2),
        ),
        prefixIcon: const Icon(Icons.sms, color: DesignColors.textTertiary),
        // >=44px tap target for clearing the code field.
        suffixIcon: IconButton(
          tooltip: 'Clear code',
          constraints: const BoxConstraints(
              minWidth: DesignSpacing.xl + 24,
              minHeight: DesignSpacing.xl + 24),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, color: DesignColors.textTertiary),
          onPressed: () => controller.clear(),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
