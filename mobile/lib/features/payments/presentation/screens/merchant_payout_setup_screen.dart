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
  State<MerchantPayoutSetupScreen> createState() =>
      _MerchantPayoutSetupScreenState();
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
  bool _isChangingPayout = false;
  bool _showAccountNumber = false;

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
    _accountNumber.addListener(_onAccountNumberChanged);
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
    _accountNumber.removeListener(_onAccountNumberChanged);
    _accountNumber.dispose();
    super.dispose();
  }

  void _onAccountNumberChanged() {
    if (mounted) setState(() {});
  }

  String _bankNameForCode(String? code) {
    for (final bank in _banks) {
      if (bank['code']?.toString() == code) {
        return bank['name']?.toString() ?? 'Selected bank';
      }
    }
    return _account?['bankName']?.toString() ?? 'Choose your bank';
  }

  Widget _enter(int step, Widget child) {
    final start = step * 0.12;
    final end = math.min(start + 0.48, 1.0);
    return AnimatedBuilder(
      animation: _entryController,
      child: child,
      builder: (context, child) {
        final raw =
            ((_entryController.value - start) / (end - start)).clamp(0.0, 1.0);
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
    setState(() {
      _loading = true;
      _error = null;
    });
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
    if (_bankCode == null ||
        !RegExp(r'^\d{6,20}$').hasMatch(accountNumber) ||
        !_ownsAccount ||
        !_acceptedPaymentTerms) {
      setState(() => _error =
          'Select a bank, enter its account number, confirm ownership, and accept the payment terms.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
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
        _isChangingPayout = false;
      });
      final verified =
          account['status'] == 'ACTIVE' && account['paystackVerified'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(verified
              ? 'Paystack verified your payout account.'
              : 'Payout details saved. Paystack must verify this account before customer M-Pesa and debt payments are enabled. Cash sales remain available.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedBankCode = _account?['bankCode']?.toString();
    final savedAccountLast4 = _account?['accountLast4']?.toString() ?? '';
    final savedAccountHolder = _account?['accountName']?.toString();
    final paystackVerified = _account?['paystackVerified'] == true ||
        (_account?['paystackVerified'] == null &&
            _account?['accountHolderVerified'] == true);
    final ready = _account?['status'] == 'ACTIVE' && paystackVerified;
    final needsVerification = _account?['status'] == 'PENDING_VERIFICATION';
    return Scaffold(
      appBar:
          const BrandedAppBar(title: 'Customer payments', showBackButton: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth >= 640 ? 28.0 : 16.0;
                return RefreshIndicator(
                  onRefresh: _load,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                            horizontalPadding, 18, horizontalPadding, 32),
                        children: [
                          _enter(
                              0,
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Where your sales money goes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Connect your business bank account to accept customer M-Pesa and debt payments. Paystack sends those payments to this account. Cash sales work without payout setup. Your Counterbase plan is billed separately.',
                                  ),
                                ],
                              )),
                          const SizedBox(height: 14),
                          _enter(
                              1,
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.phone_android_rounded,
                                              color: DesignColors.accent),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'M-PESA phone, Till and Paybill',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Paystack supports these through its Transfers service. Counterbase’s current direct split-settlement route verifies bank subaccounts. Wallet payouts need Paystack balance settlement and separate transfer-fee handling before they can be enabled safely.',
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          for (final destination in const [
                                            'M-PESA number',
                                            'M-PESA Till',
                                            'M-PESA Paybill',
                                          ])
                                            Chip(
                                              avatar: const Icon(
                                                  Icons.lock_outline_rounded,
                                                  size: 15),
                                              label: Text(destination),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                          const SizedBox(height: 20),
                          if ((ready || needsVerification) &&
                              !_isChangingPayout) ...[
                            _enter(
                                2,
                                _BankSettlementCard(
                                  key: ValueKey('saved:$savedBankCode'),
                                  bankName: _account?['bankName']?.toString() ??
                                      _bankNameForCode(_bankCode),
                                  accountNumber: savedAccountLast4,
                                  accountHolder: savedAccountHolder,
                                  animation: _flowController,
                                  verified: ready,
                                )),
                            const SizedBox(height: 16),
                          ],
                          _enter(
                              2,
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 380),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
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
                                  key: ValueKey('$ready:$needsVerification'),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Icon(
                                              ready
                                                  ? Icons.check_circle_rounded
                                                  : Icons.info_outline_rounded,
                                              color: ready
                                                  ? DesignColors.success
                                                  : DesignColors.warning),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                                ready
                                                    ? 'Payout account verified'
                                                    : needsVerification
                                                        ? 'Paystack verification pending'
                                                        : 'Payout account needed',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ]),
                                        AnimatedSize(
                                          duration:
                                              const Duration(milliseconds: 320),
                                          curve: Curves.easeOutCubic,
                                          child: ready
                                              ? Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Row(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .verified_user_rounded,
                                                              size: 18,
                                                              color:
                                                                  DesignColors
                                                                      .success),
                                                          SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                                'Paystack has verified this payout account'),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8),
                                                      const Text(
                                                          'New customer payments will use this account. Payments already started keep their original payout route.'),
                                                    ],
                                                  ),
                                                )
                                              : needsVerification
                                                  ? const Padding(
                                                      padding: EdgeInsets.only(
                                                          top: 8),
                                                      child: Text(
                                                        'Paystack has received your details and is verifying the account. Customer M-Pesa and debt payments will turn on after approval. Cash sales are available now.',
                                                      ),
                                                    )
                                                  : const SizedBox(
                                                      width: double.infinity,
                                                      height: 0),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )),
                          const SizedBox(height: 24),
                          if ((ready || needsVerification) &&
                              !_isChangingPayout)
                            _enter(
                                3,
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _isChangingPayout = true),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: Text(ready
                                      ? 'Change payout details'
                                      : 'Edit submitted details'),
                                )),
                          _enter(
                              3,
                              (ready || needsVerification) && !_isChangingPayout
                                  ? const SizedBox.shrink()
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            ready || needsVerification
                                                ? 'Payout account details'
                                                : 'Connect payout account',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge),
                                        const SizedBox(height: 12),
                                        DropdownButtonFormField<String>(
                                          initialValue: _bankCode,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Bank',
                                            prefixIcon: Icon(
                                                Icons.account_balance_outlined),
                                            border: OutlineInputBorder(),
                                          ),
                                          items: _banks
                                              .map((bank) =>
                                                  DropdownMenuItem<String>(
                                                    value: bank['code']
                                                        ?.toString(),
                                                    child: Text(
                                                      bank['name']
                                                              ?.toString() ??
                                                          '',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ))
                                              .toList(),
                                          onChanged: _saving || _banks.isEmpty
                                              ? null
                                              : (value) => setState(() {
                                                    _bankCode = value;
                                                    _showAccountNumber = false;
                                                  }),
                                        ),
                                        if (_bankCode != null) ...[
                                          const SizedBox(height: 14),
                                          _BankSettlementCard(
                                            key: ValueKey('editing:$_bankCode'),
                                            bankName:
                                                _bankNameForCode(_bankCode),
                                            accountNumber: _accountNumber
                                                    .text.isNotEmpty
                                                ? _accountNumber.text
                                                : (_bankCode == savedBankCode
                                                    ? savedAccountLast4
                                                    : ''),
                                            accountHolder:
                                                _bankCode == savedBankCode
                                                    ? savedAccountHolder
                                                    : null,
                                            animation: _flowController,
                                            verified:
                                                _bankCode == savedBankCode &&
                                                    ready,
                                            revealNumber: _showAccountNumber,
                                            onToggleReveal: _accountNumber
                                                    .text.isEmpty
                                                ? null
                                                : () => setState(() =>
                                                    _showAccountNumber =
                                                        !_showAccountNumber),
                                          ),
                                        ],
                                        if (_banks.isEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            _api.baseUrl
                                                    .contains('preview.invalid')
                                                ? 'This offline preview does not use sample banks. The connected app loads all supported Kenyan banks from Paystack.'
                                                : 'No banks were returned. Refresh to try loading the Paystack bank list again.',
                                            style: const TextStyle(
                                                color: DesignColors.warning),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _accountNumber,
                                          enabled: !_saving,
                                          keyboardType: TextInputType.number,
                                          autofillHints: const [],
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Business bank account number',
                                            prefixIcon:
                                                Icon(Icons.numbers_rounded),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        CheckboxListTile(
                                          value: _ownsAccount,
                                          contentPadding: EdgeInsets.zero,
                                          onChanged: _saving
                                              ? null
                                              : (value) => setState(() =>
                                                  _ownsAccount =
                                                      value ?? false),
                                          title: const Text(
                                              'I confirm this account belongs to my business'),
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                        ),
                                        CheckboxListTile(
                                          value: _acceptedPaymentTerms,
                                          contentPadding: EdgeInsets.zero,
                                          onChanged: _saving
                                              ? null
                                              : (value) => setState(
                                                    () =>
                                                        _acceptedPaymentTerms =
                                                            value ?? false,
                                                  ),
                                          title: const Text(
                                            'I agree to the merchant payment and settlement terms.',
                                          ),
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton(
                                            onPressed: _saving
                                                ? null
                                                : () => context.push(
                                                    '/legal/merchant-payments'),
                                            child: const Text(
                                                'Read merchant payment terms'),
                                          ),
                                        ),
                                        const Text(
                                            'Only your bank and account number are needed. Never enter a bank password, PIN, or OTP here.'),
                                        if (_error != null) ...[
                                          const SizedBox(height: 16),
                                          Text(_error!,
                                              style: const TextStyle(
                                                  color: DesignColors.error)),
                                        ],
                                      ],
                                    )),
                          if ((!ready && !needsVerification) ||
                              _isChangingPayout) ...[
                            const SizedBox(height: 20),
                            _enter(
                                4,
                                FilledButton.icon(
                                  onPressed:
                                      _saving || _banks.isEmpty ? null : _save,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: _saving
                                        ? const SizedBox(
                                            key: ValueKey('saving'),
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(
                                            key: ValueKey('ready'),
                                            Icons.verified_outlined),
                                  ),
                                  label: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: Text(
                                      _saving
                                          ? 'Verifying payout details…'
                                          : ready || needsVerification
                                              ? 'Update payout account'
                                              : 'Connect payout account',
                                      key: ValueKey(
                                          (_saving, ready, needsVerification)),
                                    ),
                                  ),
                                )),
                          ],
                          if (ready && !_isChangingPayout) ...[
                            const SizedBox(height: 12),
                            _enter(
                                4,
                                OutlinedButton(
                                    onPressed: () => context.pop(true),
                                    child: const Text('Done'))),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// An animated settlement card that appears as soon as a bank is selected.
/// Account numbers remain masked unless the merchant explicitly reveals them.
class _BankSettlementCard extends StatelessWidget {
  const _BankSettlementCard({
    super.key,
    required this.bankName,
    required this.accountNumber,
    required this.animation,
    required this.verified,
    this.accountHolder,
    this.revealNumber = false,
    this.onToggleReveal,
  });

  final String bankName;
  final String accountNumber;
  final String? accountHolder;
  final Animation<double> animation;
  final bool verified;
  final bool revealNumber;
  final VoidCallback? onToggleReveal;

  String get _displayNumber {
    final digits = accountNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '•••• •••• ••••';
    final shown = revealNumber
        ? digits
        : digits.length <= 4
            ? '••••$digits'
            : '${'•' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
    return RegExp(r'.{1,4}')
        .allMatches(shown)
        .map((match) => match.group(0)!)
        .join(' ');
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          final cardPadding = compact ? 14.0 : 18.0;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final pulse = 1 + math.sin(animation.value * math.pi * 2) * 0.025;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, value) => FadeTransition(
                  opacity: value,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.96, end: 1).animate(value),
                    child: child,
                  ),
                ),
                child: Container(
                  key: key ?? ValueKey(bankName),
                  width: double.infinity,
                  padding: EdgeInsets.all(cardPadding),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF182536), Color(0xFF34485F)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF182536).withValues(alpha: 0.20),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -42,
                        top: -66,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.07),
                            ),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Transform.scale(
                                scale: pulse,
                                child: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF874F)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFFFFA16F)
                                          .withValues(alpha: 0.45),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF874F)
                                            .withValues(alpha: 0.16),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_rounded,
                                    color: Color(0xFFFFA16F),
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'BUSINESS SETTLEMENT',
                                      style: TextStyle(
                                        color: Color(0xFFCFD7E1),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(bankName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: compact ? 14 : 15,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                              ),
                              if (onToggleReveal != null)
                                IconButton(
                                  tooltip: revealNumber
                                      ? 'Hide account number'
                                      : 'Show account number',
                                  onPressed: onToggleReveal,
                                  visualDensity: VisualDensity.compact,
                                  color: Colors.white.withValues(alpha: 0.72),
                                  icon: Icon(revealNumber
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined),
                                )
                              else
                                Icon(Icons.contactless_rounded,
                                    color:
                                        Colors.white.withValues(alpha: 0.62)),
                            ],
                          ),
                          SizedBox(height: compact ? 14 : 17),
                          Row(
                            children: [
                              const _BankCardChip(),
                              const SizedBox(width: 10),
                              Icon(Icons.wifi_rounded,
                                  size: 21,
                                  color: Colors.white.withValues(alpha: 0.66)),
                              const Spacer(),
                              Text('KES · KENYA',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  )),
                            ],
                          ),
                          SizedBox(height: compact ? 10 : 12),
                          Semantics(
                            label: 'Business bank account number',
                            child: Text(
                              _displayNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 17 : 19,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 9 : 11),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('ACCOUNT HOLDER',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.54),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.9,
                                        )),
                                    const SizedBox(height: 3),
                                    Text(
                                      accountHolder?.trim().isNotEmpty == true
                                          ? accountHolder!.trim()
                                          : 'Confirmed by Paystack after saving',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.88),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                verified
                                    ? Icons.verified_rounded
                                    : Icons.lock_rounded,
                                size: 16,
                                color: verified
                                    ? const Color(0xFF77E0A8)
                                    : Colors.white.withValues(alpha: 0.66),
                              ),
                              const SizedBox(width: 5),
                              Text(verified ? 'VERIFIED' : 'SECURE',
                                  style: TextStyle(
                                    color: verified
                                        ? const Color(0xFF9BE8BC)
                                        : Colors.white.withValues(alpha: 0.72),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  )),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
}

class _BankCardChip extends StatelessWidget {
  const _BankCardChip();

  @override
  Widget build(BuildContext context) => Container(
        width: 43,
        height: 31,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8D3A1), Color(0xFFB99655)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF2DDAA), width: 0.8),
        ),
        child: CustomPaint(painter: _BankChipPainter()),
      );
}

class _BankChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF80683D).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 17, height: 13),
        const Radius.circular(3),
      ),
      stroke,
    );
    canvas.drawLine(
        Offset(center.dx, 0), Offset(center.dx, center.dy - 6.5), stroke);
    canvas.drawLine(Offset(center.dx, center.dy + 6.5),
        Offset(center.dx, size.height), stroke);
    canvas.drawLine(
        Offset(0, center.dy), Offset(center.dx - 8.5, center.dy), stroke);
    canvas.drawLine(Offset(center.dx + 8.5, center.dy),
        Offset(size.width, center.dy), stroke);
  }

  @override
  bool shouldRepaint(covariant _BankChipPainter oldDelegate) => false;
}
