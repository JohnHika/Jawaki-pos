import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/ai-billing/presentation/services/ai_billing_service.dart';

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
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  bool _isMpesaReady = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _checkMpesaAvailability();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkMpesaAvailability() async {
    try {
      // Try to open M-Pesa app
      await _billingService.launchMpesa();
      if (mounted) setState(() => _isMpesaReady = true);
    } catch (e) {
      if (mounted) setState(() => _isMpesaReady = false);
    }
  }

  Future<void> _openMpesa() async {
    try {
      await _billingService.launchMpesa();
    } catch (e) {
      setState(() => _error = 'Failed to open M-Pesa. Make sure it is installed.');
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the M-Pesa confirmation code');
      return;
    }
    if (code.length < 5) {
      setState(() => _error = 'Invalid code. Please check your SMS.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _billingService.submitPayment(widget.branchId, code);
      if (mounted) {
        setState(() => _successMessage = result['message']);
        _codeController.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).cardColor;
    final textPrimaryColor = Theme.of(context).textTheme.headlineSmall?.color;
    final textSecondaryColor = Theme.of(context).textTheme.bodyLarge?.color;
    final textHintColor = Theme.of(context).textTheme.labelMedium?.color;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        title: Text('Subscribe to Axon AI'),
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimaryColor),
          onPressed: Navigator.of(context).pop,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payment instructions
              _SectionCard(
                title: 'How to Subscribe',
                children: [
                  _InstructionStep(
                    number: 1,
                    title: 'Send M-Pesa',
                    description: 'Send exactly 600 KES to your store\'s M-Pesa number',
                    highlight: '0742126582',
                    primary: primary,
                  ),
                  _InstructionStep(
                    number: 2,
                    title: 'Enter Code',
                    description: 'Enter the confirmation code from your SMS',
                  ),
                ],
              ).animate().slideX(begin: -0.2, duration: 400.ms),

              const SizedBox(height: 24),

              // Enter code section
              Text(
                'Enter M-Pesa Confirmation Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textPrimaryColor,
                ),
              ),
              const SizedBox(height: 12),

              _CodeInputField(
                controller: _codeController,
                onSubmitted: _submitCode,
              ).animate().scale(duration: 500.ms),

              const SizedBox(height: 16),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        'Activate Subscription',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                ),
              ).animate().fade(duration: 500.ms, delay: 200.ms),

              const SizedBox(height: 16),

              // Result message
              if (_successMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _openMpesa(),
                  icon: Icon(Icons.mobile_friendly, size: 20),
                  label: Text('Open M-Pesa App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ).animate().slideY(begin: 0.2, duration: 400.ms),
              ],

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // M-Pesa section
              _MpesaButton(
                isReady: _isMpesaReady,
                onTap: _openMpesa,
                primary: primary,
              ).animate().slideY(begin: 0.3, duration: 500.ms),

              const SizedBox(height: 24),

              // Trial info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '7-Day Free Trial',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: textPrimaryColor,
                            ),
                          ),
                          Text(
                            'After trial, subscribe for 600 KES/month',
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primary.withOpacity(0.3)),
                      ),
                      child: Text(
                        '600 KES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

              const SizedBox(height: 24),

              // Terms
              Text(
                'By subscribing, you agree to our Terms of Service and Privacy Policy. '
                'Subscription auto-renews monthly unless cancelled.',
                style: TextStyle(
                  color: textHintColor,
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
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).cardColor;
    final primary = Theme.of(context).colorScheme.primary;
    final textPrimary = Theme.of(context).textTheme.headlineSmall?.color;
    final border = BorderSide(color: Colors.grey.shade300);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 16),
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
  final Color? primary;

  const _InstructionStep({
    required this.number,
    required this.title,
    required this.description,
    this.highlight,
    this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = Theme.of(context).textTheme.headlineSmall?.color;
    final textSecondary = Theme.of(context).textTheme.bodyLarge?.color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primary ?? Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (highlight != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (primary ?? Colors.blue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: (primary ?? Colors.blue).withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          highlight!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.copy, size: 16, color: primary),
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
    final border = BorderSide(color: Colors.grey.shade300);

    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      keyboardType: TextInputType.text,
      onSubmitted: (_) => onSubmitted(),
      decoration: InputDecoration(
        hintText: 'Enter M-Pesa code (e.g., QK8W3X)',
        hintStyle: TextStyle(color: Theme.of(context).textTheme.labelMedium?.color, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: border,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: border,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary ?? Colors.blue, width: 2),
        ),
        prefixIcon: Icon(Icons.sms, color: Theme.of(context).textTheme.labelMedium?.color),
        suffixIcon: IconButton(
          icon: Icon(Icons.close, color: Theme.of(context).textTheme.labelMedium?.color),
          onPressed: () => controller.clear(),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _MpesaButton extends StatelessWidget {
  final bool isReady;
  final VoidCallback onTap;
  final Color? primary;

  const _MpesaButton({
    required this.isReady,
    required this.onTap,
    this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = Theme.of(context).textTheme.headlineSmall?.color;
    final textSecondary = Theme.of(context).textTheme.bodyLarge?.color;
    final textHint = Theme.of(context).textTheme.labelMedium?.color;
    final surface = Theme.of(context).cardColor;
    final border = BorderSide(color: Colors.grey.shade300);

    return InkWell(
      onTap: isReady ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isReady ? Colors.green.withOpacity(0.1) : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isReady ? Colors.green.withOpacity(0.3) : border.color,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isReady ? Colors.green : border.color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mobile_friendly,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open M-Pesa App',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    isReady ? 'Tap to open' : 'M-Pesa app not found',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
