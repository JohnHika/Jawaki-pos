import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../core/widgets/loading_button.dart';
import '../../services/api_service.dart';
import '../../services/sms_service.dart';

class AiSubscribeScreen extends StatefulWidget {
  const AiSubscribeScreen({super.key});

  @override
  State<AiSubscribeScreen> createState() => _AiSubscribeScreenState();
}

class _AiSubscribeScreenState extends State<AiSubscribeScreen> {
  int _currentStep = 0;
  bool _isLoading = false;
  final TextEditingController _mpesaCodeController = TextEditingController();
  String? _error;
  String? _paymentId;
  bool _isSuccess = false;
  String _storeId = 'store_001';

  static const List<String> _steps = [
    'Pricing',
    'Payment',
    'Verify',
    'Complete',
  ];

  @override
  void dispose() {
    _mpesaCodeController.dispose();
    super.dispose();
  }

  Future<void> _initiatePayment() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final result = await apiService.initiateSubscription(
        _storeId,
        'DEMO${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        if (result?['error'] != null) {
          setState(() {
            _error = result?['error'] as String? ?? 'Payment failed';
            _isLoading = false;
          });
        } else {
          setState(() {
            _paymentId = result?['payment_id'] as String? ?? '';
            _currentStep = 1;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyPayment() async {
    final code = _mpesaCodeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter the M-Pesa confirmation code');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // First verify via SMS service
      final smsService = context.read<SmsService>();
      final smsVerified = await smsService.verifyMpesaCode(code);

      if (!smsVerified && mounted) {
        setState(() {
          _error = 'Invalid M-Pesa code. Please check and try again.';
          _isLoading = false;
        });
        return;
      }

      // Then verify via API
      final apiService = context.read<ApiService>();
      final result = await apiService.verifyPayment(
        _paymentId ?? '',
        code,
      );

      if (mounted) {
        if (result['success'] == true) {
          setState(() {
            _currentStep = 2;
            _isLoading = false;
            _isSuccess = true;
          });
        } else {
          setState(() {
            _error = result['error'] as String? ?? 'Verification failed';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // Mock success for demo
        setState(() {
          _currentStep = 2;
          _isLoading = false;
          _isSuccess = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Subscription'),
      ),
      body: _isSuccess ? _buildSuccessScreen() : _buildPaymentFlow(),
    );
  }

  Widget _buildPaymentFlow() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step indicator
          _buildStepIndicator(),
          const SizedBox(height: 24),

          // Step content
          if (_currentStep == 0) _buildPricingStep(),
          if (_currentStep == 1) _buildPaymentStep(),
          if (_currentStep == 2) _buildVerifyStep(),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JawakiTheme.accentRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: JawakiTheme.accentRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: JawakiTheme.accentRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: JawakiTheme.accentRed,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(_steps.length, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;
        final stepNum = index + 1;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted || isCurrent
                        ? JawakiTheme.primaryTeal
                        : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : Text(
                            '$stepNum',
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.grey[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[index],
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrent ? JawakiTheme.primaryTeal : Colors.grey,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPricingStep() {
    return Card(
      elevation: 4,
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
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AI Assistant',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'KES ${ApiConstants.aiPrice}/month',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 16),
            _buildFeatureRow(Icons.show_chart, 'Sales insights & reports'),
            _buildFeatureRow(Icons.inventory, 'Inventory forecasting'),
            _buildFeatureRow(Icons.people, 'Customer behavior analysis'),
            _buildFeatureRow(Icons.trending_up, 'Profit margin tracking'),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.card_giftcard, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'First 7 days free! Cancel anytime.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: 'Start Free Trial',
              icon: Icons.arrow_forward,
              isLoading: _isLoading,
              backgroundColor: JawakiTheme.accentOrange,
              onPressed: _initiatePayment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStep() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Make Payment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // M-Pesa details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JawakiTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_android, color: JawakiTheme.primaryDeepBlue),
                      SizedBox(width: 8),
                      Text(
                        'M-Pesa Payment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: JawakiTheme.primaryDeepBlue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  _PaymentRow('Paybill:', '247247'),
                  SizedBox(height: 8),
                  _PaymentRow('Account:', 'JAWAKI-AI'),
                  SizedBox(height: 8),
                  _PaymentRow('Amount:', 'KES ${ApiConstants.aiPrice}'),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'After sending M-Pesa, enter the confirmation code below:',
              style: TextStyle(
                fontSize: 14,
                color: JawakiTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mpesaCodeController,
              decoration: const InputDecoration(
                labelText: 'M-Pesa Confirmation Code',
                hintText: 'e.g. ABC123XYZ',
                prefixIcon: Icon(Icons.confirmation_number),
              ),
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 20),
            LoadingButton(
              label: 'Verify via SMS',
              icon: Icons.sms,
              isLoading: _isLoading,
              onPressed: _verifyPayment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifyStep() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.hourglass_top,
              size: 64,
              color: JawakiTheme.accentOrange,
            ),
            const SizedBox(height: 16),
            const Text(
              'Verifying Payment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Please wait while we verify your M-Pesa payment...',
              style: TextStyle(
                fontSize: 14,
                color: JawakiTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                // Mock: auto-verify after waiting
                setState(() => _isSuccess = true);
              },
              child: const Text('Tap to simulate verification'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: JawakiTheme.accentGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Text(
                '🎉',
                style: TextStyle(fontSize: 56),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'AI Activated!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: JawakiTheme.accentGreen,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '30 days remaining',
              style: TextStyle(
                fontSize: 16,
                color: JawakiTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JawakiTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: JawakiTheme.accentGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You now have full access to Jawaki AI Assistant features.',
                      style: TextStyle(
                        fontSize: 14,
                        color: JawakiTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chat),
                label: const Text('Start Chatting'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String label;
  final String value;

  const _PaymentRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: JawakiTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: JawakiTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
