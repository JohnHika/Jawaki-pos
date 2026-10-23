import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/legal/policy_catalog.dart';
import '../../../../core/theme/design_system.dart';

/// Owner setup for routing customer M-Pesa payments to the shop's bank.
/// The app never asks for online-banking passwords, PINs, or OTPs.
class MerchantPayoutSetupScreen extends StatefulWidget {
  const MerchantPayoutSetupScreen({super.key});

  @override
  State<MerchantPayoutSetupScreen> createState() => _MerchantPayoutSetupScreenState();
}

class _MerchantPayoutSetupScreenState extends State<MerchantPayoutSetupScreen>
    with TickerProviderStateMixin {
  final _accountNumber = TextEditingController();
  final _api = getIt<ApiClient>();
  late final AnimationController _entryController;
  late final AnimationController _flowController;
  List<Map<String, dynamic>> _banks = const [];
  Map<String, dynamic>? _account;
  String? _bankCode;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _ownsAccount = false;
  bool _acceptedPaymentTerms = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entryController.value = 1;
      _flowController.stop();
    } else if (!_flowController.isAnimating) {
      _flowController.repeat();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _flowController.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  Widget _enter(int step, Widget child) {
    final start = step * 0.12;
    final end = math.min(start + 0.48, 1.0);
    return AnimatedBuilder(
      animation: _entryController,
      child: child,
      builder: (context, child) {
        final raw = ((_entryController.value - start) / (end - start))
            .clamp(0.0, 1.0);
        final progress = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 16),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final account = await _api.getMerchantPayoutAccount();
      final banks = await _api.getMerchantPayoutBanks();
      if (!mounted) return;
      setState(() {
        _account = account;
        _banks = banks;
        _bankCode = account['bankCode']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        return message is List ? message.join(', ') : message.toString();
      }
    }
    return 'Could not reach payment setup. Check your connection and try again.';
  }

  Future<void> _save() async {
    final accountNumber = _accountNumber.text.replaceAll(RegExp(r'\s+'), '');
    if (_bankCode == null || !RegExp(r'^\d{6,20}$').hasMatch(accountNumber) ||
        !_ownsAccount || !_acceptedPaymentTerms) {
      setState(() => _error = 'Select a bank, enter its account number, confirm ownership, and accept the payment terms.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await _api.acceptLegalPolicy(
        policyType: 'MERCHANT_PAYMENT_TERMS',
        policyVersion: policyVersion('MERCHANT_PAYMENT_TERMS'),
      );
      final account = await _api.configureMerchantPayout({
        'bankCode': _bankCode,
        'accountNumber': accountNumber,
        'confirmAccountOwnership': true,
      });
      if (!mounted) return;
      _accountNumber.clear();
      setState(() {
        _account = account;
        _ownsAccount = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business payout account connected.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _account?['status'] == 'ACTIVE' &&
        _account?['accountHolderVerified'] == true;
    final needsVerification = _account?['status'] == 'PENDING_VERIFICATION';
    return Scaffold(
      appBar: const BrandedAppBar(title: 'Customer payments', showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _enter(0, _PayoutRouteCard(animation: _flowController)),
                  const SizedBox(height: 24),
                  _enter(1, Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Where your sales money goes',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                        'Connect your business bank account to accept customer M-Pesa payments in Counterbase. Paystack sends your share to this account. Your Counterbase plan is billed separately.',
                      ),
                    ],
                  )),
                  const SizedBox(height: 20),
                  _enter(2, AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Card(
                      key: ValueKey(ready),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                  color: ready ? DesignColors.success : DesignColors.warning),
                              const SizedBox(width: 8),
                              Text(ready
                                  ? 'Payout account verified'
                                  : needsVerification
                                      ? 'Verify payout account'
                                      : 'Payout account needed',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ]),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              child: ready
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${_account?['bankName']} ·•••• ${_account?['accountLast4']}'),
                                          Text('Account holder: ${_account?['accountName']}'),
                                          const SizedBox(height: 6),
                                          const Row(
                                            children: [
                                              Icon(Icons.verified_user_rounded,
                                                  size: 18, color: DesignColors.success),
                                              SizedBox(width: 6),
                                              Expanded(
                                                child: Text('Account holder confirmed by Paystack'),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Text('New customer payments will use this account. Payments already started keep their original payout route.'),
                                        ],
                                      ),
                                    )
                                  : needsVerification
                                      ? const Padding(
                                          padding: EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Paystack did not return an account holder name for these saved details. Re-enter the bank and account number to verify them before accepting payments.',
                                          ),
                                        )
                                      : const SizedBox(width: double.infinity, height: 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 24),
                  _enter(3, Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ready ? 'Change payout account' : 'Connect payout account',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _bankCode,
                        decoration: const InputDecoration(
                          labelText: 'Bank', prefixIcon: Icon(Icons.account_balance_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: _banks.map((bank) => DropdownMenuItem<String>(
                          value: bank['code']?.toString(),
                          child: Text(bank['name']?.toString() ?? ''),
                        )).toList(),
                        onChanged: _saving || _banks.isEmpty
                            ? null
                            : (value) => setState(() => _bankCode = value),
                      ),
                      if (_banks.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _api.baseUrl.contains('preview.invalid')
                              ? 'This offline preview does not use sample banks. The connected app loads all supported Kenyan banks from Paystack.'
                              : 'No banks were returned. Refresh to try loading the Paystack bank list again.',
                          style: const TextStyle(color: DesignColors.warning),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _accountNumber,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        autofillHints: const [],
                        decoration: const InputDecoration(
                          labelText: 'Business bank account number',
                          prefixIcon: Icon(Icons.numbers_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _ownsAccount,
                        contentPadding: EdgeInsets.zero,
                        onChanged: _saving ? null : (value) => setState(() => _ownsAccount = value ?? false),
                        title: const Text('I confirm this account belongs to my business'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _acceptedPaymentTerms,
                        contentPadding: EdgeInsets.zero,
                        onChanged: _saving
                            ? null
                            : (value) => setState(
                                  () => _acceptedPaymentTerms = value ?? false,
                                ),
                        title: const Text(
                          'I agree to the merchant payment and settlement terms.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _saving
                              ? null
                              : () => context.push('/legal/merchant-payments'),
                          child: const Text('Read merchant payment terms'),
                        ),
                      ),
                      const Text('Only your bank and account number are needed. Never enter a bank password, PIN, or OTP here.'),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: const TextStyle(color: DesignColors.error)),
                      ],
                    ],
                  )),
                  const SizedBox(height: 20),
                  _enter(4, FilledButton.icon(
                    onPressed: _saving || _banks.isEmpty ? null : _save,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _saving
                          ? const SizedBox(key: ValueKey('saving'), width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(key: ValueKey('ready'), Icons.verified_outlined),
                    ),
                    label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Text(
                        _saving
                            ? 'Verifying payout details…'
                            : ready ? 'Update payout account' : 'Connect payout account',
                        key: ValueKey((_saving, ready)),
                      ),
                    ),
                  )),
                  if (ready) ...[
                    const SizedBox(height: 12),
                    _enter(4, OutlinedButton(
                      onPressed: () => context.pop(true), child: const Text('Done'))),
                  ],
                ],
              ),
            ),
    );
  }
}

/// A calm, animated explanation of the three-party settlement route.
/// The moving point represents the payment state, not a confirmed payout.
class _PayoutRouteCard extends StatelessWidget {
  const _PayoutRouteCard({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF17202B), Color(0xFF263443)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17202B).withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFFF874F), shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            const Text('PAYMENT ROUTING', style: TextStyle(
              color: Color(0xFFE5E9EF), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.5,
            )),
            const Spacer(),
            Icon(Icons.lock_outline_rounded,
                size: 16, color: Colors.white.withValues(alpha: 0.60)),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 98,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _PayoutFlowPainter(animation)),
                ),
                Row(children: [
                  _routeNode(Icons.shopping_bag_outlined, 'Customer'),
                  _routeNode(Icons.account_balance_wallet_outlined, 'Paystack'),
                  _routeNode(Icons.account_balance_outlined, 'Your bank'),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('Product sales settle to your business account',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13, fontWeight: FontWeight.w500,
            )),
        ],
      ),
    );
  }

  Widget _routeNode(IconData icon, String label) => Expanded(
    child: Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: const Color(0xFFFFA16F), size: 23),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 11, fontWeight: FontWeight.w600,
        )),
      ],
    ),
  );
}

class _PayoutFlowPainter extends CustomPainter {
  const _PayoutFlowPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    const y = 26.0;
    final start = size.width / 6;
    final end = size.width - start;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(start, y), Offset(end, y), line);

    for (final x in [start, size.width / 2, end]) {
      canvas.drawCircle(Offset(x, y), 3, Paint()
        ..color = Colors.white.withValues(alpha: 0.32));
    }

    final t = Curves.easeInOutCubic.transform(animation.value);
    final x = start + (end - start) * t;
    final glow = Paint()
      ..color = const Color(0xFFFF874F).withValues(alpha: 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(Offset(x, y), 8, glow);
    canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = const Color(0xFFFFB28D));
  }

  @override
  bool shouldRepaint(covariant _PayoutFlowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
