import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/till_guard.dart';
import '../../../accountability/data/till_guard_service.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../../../customers/presentation/widgets/add_customer_sheet.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../../domain/cash_tender.dart';
import '../providers/payment_provider.dart';
import '../widgets/cash_tender_sheet.dart';

enum PaymentMethod {
  cash,
  mpesa,
  debt,
  split,
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  PaymentMethod? _selectedMethod;
  final _phoneController = TextEditingController();
  String? _payoutStatus;
  Map<String, dynamic>? _payoutAccount;
  bool _paystackPayoutVerified = false;
  bool _checkingPayoutStatus = true;

  bool get _canAcceptMpesa =>
      _payoutStatus == 'ACTIVE' && _paystackPayoutVerified;

  @override
  void initState() {
    super.initState();
    _refreshPayoutStatus();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshPayoutStatus() async {
    if (mounted) setState(() => _checkingPayoutStatus = true);
    try {
      final account = await getIt<ApiClient>().getMerchantPayoutAccount();
      if (!mounted) return;
      setState(() {
        _payoutAccount = account;
        _payoutStatus = account['status']?.toString().toUpperCase();
        _paystackPayoutVerified = account['paystackVerified'] == true;
        _checkingPayoutStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _payoutAccount = null;
        _payoutStatus = 'UNKNOWN';
        _paystackPayoutVerified = false;
        _checkingPayoutStatus = false;
      });
    }
  }

  Future<void> _openPayoutSettings() async {
    await context.push('/payments/setup');
    if (mounted) {
      ref.read(paymentProvider.notifier).clearError();
      await _refreshPayoutStatus();
    }
  }

  Future<void> _showPayoutNotReady() async {
    final status = _payoutStatus;
    final title = _checkingPayoutStatus
        ? 'Checking payment setup'
        : status == 'NOT_CONFIGURED'
            ? 'Connect a payout account'
            : status == 'PENDING_VERIFICATION'
                ? 'Paystack verification pending'
                : status == 'INACTIVE'
                    ? 'Payout account inactive'
                    : 'M-Pesa is unavailable';
    final message = _checkingPayoutStatus
        ? 'Please wait while Counterbase checks your Paystack payout account.'
        : status == 'NOT_CONFIGURED'
            ? 'Add your business bank account in Customer payments before accepting M-Pesa.'
            : status == 'PENDING_VERIFICATION'
                ? 'Paystack must verify the business bank account before M-Pesa payments can be accepted.'
                : status == 'INACTIVE'
                    ? 'Paystack has marked this payout account inactive. Review it in Customer payments.'
                    : 'Counterbase could not confirm your Paystack payout status. Check your connection and try again.';

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(
          DesignSpacing.xl,
          DesignSpacing.sm,
          DesignSpacing.xl,
          DesignSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: DesignSpacing.sm),
            Text(message, style: Theme.of(sheetContext).textTheme.bodyMedium),
            const SizedBox(height: DesignSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: 'Open Customer payments',
                icon: Icons.account_balance_rounded,
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _openPayoutSettings();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isPayoutError(String? message) =>
      message?.toLowerCase().contains('payout account') == true ||
      message?.toLowerCase().contains('payout bank account') == true ||
      message?.toLowerCase().contains('customer payments') == true;

  Widget _buildPayoutStatusNotice() {
    final pending = _payoutStatus == 'PENDING_VERIFICATION';
    final title =
        pending ? 'Paystack verification pending' : 'M-Pesa setup needed';
    final detail = pending
        ? 'Paystack must verify your business bank account before customers can pay by M-Pesa.'
        : _payoutStatus == 'NOT_CONFIGURED'
            ? 'Connect your business bank account to accept customer M-Pesa payments.'
            : _payoutStatus == 'INACTIVE'
                ? 'Your payout account is inactive. Review it in Customer payments.'
                : 'We could not confirm your payout status. Check it in Customer payments.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: DesignColors.warning),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: DesignSpacing.xs),
                Text(detail),
                TextButton.icon(
                  onPressed: _openPayoutSettings,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Customer payments'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final paymentState = ref.watch(paymentProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shopName = ref.watch(tenantIdentityProvider).companyName;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: AppBackButton(
          color:
              isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary,
          isDark: isDark,
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Payment',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: DesignSpacing.xl,
            letterSpacing: -0.5,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor:
            isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order Total Card — full width (the column is start-aligned, so
            // without this the card shrinks to its text and sits off-centre).
            SizedBox(
              width: double.infinity,
              child: GlassCard(
                padding: const EdgeInsets.all(DesignSpacing.xl),
                borderRadius: DesignSpacing.radiusXl,
                blur: 8,
                tint: DesignColors.accent.withValues(alpha: 0.08),
                borderColor: DesignColors.accent.withValues(alpha: 0.15),
                child: Column(
                  children: [
                    Text(
                      'Total Amount',
                      style: TextStyle(
                        color: isDark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary,
                        fontSize: DesignType.chatBody,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    Text(
                      'KES ${cart.total.toStringAsFixed(2)}',
                      style: DesignType.numeric(
                        color: isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.xs),
                    Text(
                      '${cart.itemCount} ${cart.itemCount == 1 ? 'item' : 'items'}',
                      style: TextStyle(
                        color: isDark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary,
                        fontSize: DesignType.chatBody,
                      ),
                    ),
                    if (cart.customerName != null) ...[
                      const SizedBox(height: DesignSpacing.md - 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DesignSpacing.md + 2,
                            vertical: DesignSpacing.sm - 2),
                        decoration: BoxDecoration(
                          color: DesignColors.accent.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                          border: Border.all(
                              color:
                                  DesignColors.accent.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_rounded,
                                size: 15, color: DesignColors.accent),
                            const SizedBox(width: DesignSpacing.sm - 2),
                            Text(
                              cart.customerName!,
                              style: const TextStyle(
                                  color: DesignColors.accent,
                                  fontSize: DesignType.chatBody - 1,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: DesignSpacing.xxl),

            // Select Payment Method
            const SectionHeader(
              title: 'Payment Method',
              subtitle: 'Choose how to pay',
            ),
            const SizedBox(height: DesignSpacing.sm),

            // Cash
            _PaymentMethodTile(
              icon: Icons.money_rounded,
              title: 'Cash',
              subtitle: 'Pay with cash',
              color: DesignColors.accent,
              isSelected: _selectedMethod == PaymentMethod.cash,
              onTap: () => setState(() => _selectedMethod = PaymentMethod.cash),
            ),
            const SizedBox(height: DesignSpacing.md - 2),

            // M-Pesa
            _PaymentMethodTile(
              icon: Icons.phone_android_rounded,
              title: 'M-Pesa',
              subtitle: _checkingPayoutStatus
                  ? 'Checking Paystack payout account'
                  : _canAcceptMpesa
                      ? 'Customer pays $shopName through Paystack'
                      : 'Requires a verified business payout account',
              color: DesignColors.accent,
              isSelected: _selectedMethod == PaymentMethod.mpesa,
              onTap: () => _selectMpesa(
                cart.total,
                hasPendingRequest: paymentState.currentTransactionId != null,
              ),
            ),
            const SizedBox(height: DesignSpacing.md - 2),

            if (!_checkingPayoutStatus && !_canAcceptMpesa) ...[
              _buildPayoutStatusNotice(),
              const SizedBox(height: DesignSpacing.md - 2),
            ],

            // Debt (sell now, customer pays later)
            _PaymentMethodTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Add to Debt',
              subtitle: cart.customerId == null
                  ? 'Choose or add a customer to continue'
                  : 'Customer pays later',
              color: DesignColors.accent,
              isSelected: _selectedMethod == PaymentMethod.debt,
              onTap: () async {
                if (cart.customerId == null) {
                  final customer = await _showCustomerPicker();
                  if (customer == null || !mounted) return;
                  ref.read(cartProvider.notifier).setCustomer(
                        customer.id,
                        customerName: customer.name,
                      );
                }
                if (mounted) {
                  setState(() => _selectedMethod = PaymentMethod.debt);
                }
              },
            ),
            const SizedBox(height: DesignSpacing.md - 2),

            // Split
            _PaymentMethodTile(
              icon: Icons.call_split_rounded,
              title: 'Split Payment',
              subtitle: 'Part cash, part debt',
              color: DesignColors.accent,
              isSelected: _selectedMethod == PaymentMethod.split,
              onTap: () =>
                  setState(() => _selectedMethod = PaymentMethod.split),
            ),

            if (_selectedMethod == PaymentMethod.mpesa &&
                paymentState.currentTransactionId != null) ...[
              const SizedBox(height: DesignSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  border: Border.all(
                      color: DesignColors.accent.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.phone_android_rounded,
                      color: DesignColors.accent),
                  const SizedBox(width: DesignSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment to $shopName',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'M-Pesa request sent. Ask the customer to approve it, then check the payment status. Paystack may show Counterbase on the phone prompt; confirmed funds settle to this shop’s verified payout account.',
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ],

            // Error message
            if (paymentState.error != null &&
                !_isPayoutError(paymentState.error)) ...[
              const SizedBox(height: DesignSpacing.lg),
              Container(
                padding: const EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  border: Border.all(
                      color: DesignColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: DesignColors.error, size: 20),
                    const SizedBox(width: DesignSpacing.sm),
                    Expanded(
                      child: Text(
                        paymentState.error!,
                        style: const TextStyle(
                            color: DesignColors.error,
                            fontSize: DesignType.chatBody - 1),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: DesignSpacing.xxl),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.sm,
              DesignSpacing.lg, DesignSpacing.lg),
          child: GradientButton(
            label: _getButtonText(paymentState),
            icon: Icons.payment_rounded,
            onPressed: _selectedMethod == null || paymentState.isProcessing
                ? null
                : _processPayment,
            isLoading: paymentState.isProcessing,
            height: 56,
            borderRadius: DesignSpacing.radiusLg,
          ),
        ),
      ),
    );
  }

  String _getButtonText(PaymentState paymentState) {
    switch (_selectedMethod) {
      case PaymentMethod.cash:
        return 'Confirm Cash Payment';
      case PaymentMethod.mpesa:
        return paymentState.currentTransactionId == null
            ? 'Send M-Pesa Request'
            : 'Check M-Pesa Payment';
      case PaymentMethod.debt:
        return 'Record as Debt';
      case PaymentMethod.split:
        return 'Enter Split Payment';
      case null:
        return 'Select Payment Method';
    }
  }

  Future<void> _selectMpesa(
    double total, {
    required bool hasPendingRequest,
  }) async {
    if (!_canAcceptMpesa) {
      await _showPayoutNotReady();
      return;
    }
    setState(() => _selectedMethod = PaymentMethod.mpesa);
    if (hasPendingRequest) return;
    final ready = await _showMpesaDetailsSheet(total);
    if (ready && mounted) await _processPayment();
  }

  Future<bool> _showMpesaDetailsSheet(double total) async {
    final formKey = GlobalKey<FormState>();
    final shopName = ref.read(tenantIdentityProvider).companyName;
    final payoutAccount = _payoutAccount ?? const <String, dynamic>{};
    final bankName = payoutAccount['bankName']?.toString().trim() ?? '';
    final accountName = payoutAccount['accountName']?.toString().trim() ?? '';
    final accountLast4 = payoutAccount['accountLast4']?.toString().trim() ?? '';
    return await showModalBottomSheet<bool>(
          useRootNavigator: true,
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (sheetContext) => Padding(
            padding: EdgeInsets.fromLTRB(
              DesignSpacing.xl,
              DesignSpacing.sm,
              DesignSpacing.xl,
              MediaQuery.viewInsetsOf(sheetContext).bottom + DesignSpacing.xl,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payment to $shopName',
                        style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: DesignSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignSpacing.md),
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                          color: DesignColors.accent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.storefront_rounded,
                              color: DesignColors.accent),
                          const SizedBox(width: DesignSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(shopName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if (accountName.isNotEmpty &&
                                    accountName.toLowerCase() !=
                                        shopName.toLowerCase()) ...[
                                  const SizedBox(height: 2),
                                  Text('Account holder: $accountName'),
                                ],
                                if (bankName.isNotEmpty ||
                                    accountLast4.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text([
                                    if (bankName.isNotEmpty) bankName,
                                    if (accountLast4.isNotEmpty)
                                      'account ending $accountLast4',
                                  ].join(' · ')),
                                ],
                                const SizedBox(height: DesignSpacing.xs),
                                Text(
                                  'Verified shop payout destination',
                                  style: Theme.of(sheetContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: DesignColors.success,
                                          fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.verified_rounded,
                              color: DesignColors.success, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: DesignSpacing.sm),
                    Text(
                      'Paystack controls the name shown in the M-Pesa PIN prompt, which may say “PAYSTACK Account no. Counterbase.” That is Paystack’s prompt label, not the shop bank account number. The app records this sale for $shopName and routes it to the verified shop payout account shown above.',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignSpacing.md),
                      decoration: BoxDecoration(
                        color: DesignColors.accent.withValues(alpha: 0.10),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                      ),
                      child: Row(children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: DesignColors.accent),
                        const SizedBox(width: DesignSpacing.md),
                        const Expanded(child: Text('Amount due')),
                        Text(
                          'KES ${total.toStringAsFixed(2)}',
                          style: DesignType.numeric(fontSize: 16),
                        ),
                      ]),
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Customer phone number',
                        hintText: '712 345 678',
                        prefixText: '+254 ',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                      ),
                      validator: (value) => _isKenyanPhone(value ?? '')
                          ? null
                          : 'Enter a valid Kenyan mobile number',
                    ),
                    const SizedBox(height: DesignSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        label: 'Send M-Pesa request',
                        icon: Icons.send_rounded,
                        height: 54,
                        borderRadius: DesignSpacing.radiusLg,
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            Navigator.pop(sheetContext, true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  String _normalizeKenyanPhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.startsWith('254')) {
      digits = digits.substring(3);
    }
    return '254$digits';
  }

  bool _isKenyanPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 9) {
      return digits.startsWith('7') || digits.startsWith('1');
    }
    if (digits.length == 10) {
      return digits.startsWith('07') || digits.startsWith('01');
    }
    return digits.length == 12 &&
        digits.startsWith('254') &&
        (digits[3] == '7' || digits[3] == '1');
  }

  /// The cart as the shop's price and discount rules see it.
  /// A coupon's share of each line lowers the price the item really sold at,
  /// so a coupon cannot hide a sale below cost, but it is the owner's own
  /// approved discount and does not count against the cashier's limit.
  List<GuardLine> _guardLines(CartState cart) {
    final shares = cart.couponShares;
    return [
      for (var i = 0; i < cart.items.length; i++)
        GuardLine(
          productId: cart.items[i].productId,
          name: cart.items[i].productName,
          quantity: cart.items[i].quantity,
          unitPrice: cart.items[i].unitPrice,
          discount: cart.items[i].discount,
          approvedDiscount: shares[i],
        ),
    ];
  }

  /// The coupon code to record with the sale, only if it actually took money off.
  String? _couponCodeFor(CartState cart) =>
      cart.couponDiscount > 0 ? cart.coupon?.code : null;

  Future<_CustomerChoice?> _showCustomerPicker() {
    return showModalBottomSheet<_CustomerChoice>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _CustomerPickerSheet(),
    );
  }

  Future<void> _processPayment({bool rulesChecked = false}) async {
    if (_selectedMethod == null) return;

    if (ref.read(paymentProvider.notifier).hasUnresolvedMerchantPayment &&
        _selectedMethod != PaymentMethod.mpesa) {
      showGlassSnackBar(
        context,
        'Check the pending M-Pesa payment before taking another method.',
        icon: Icons.pending_actions_rounded,
        color: DesignColors.warning,
      );
      return;
    }

    var cart = ref.read(cartProvider);
    final paymentNotifier = ref.read(paymentProvider.notifier);

    // Recover in place if the cashier chose debt before attaching a customer.
    // The cart and its discounts remain intact while the customer is selected.
    if (_selectedMethod == PaymentMethod.debt && cart.customerId == null) {
      final customer = await _showCustomerPicker();
      if (customer == null || !mounted) return;
      ref.read(cartProvider.notifier).setCustomer(
            customer.id,
            customerName: customer.name,
          );
      cart = ref.read(cartProvider);
    }

    // The shop's price, discount and credit rules. Checked once per sale (the
    // M-Pesa details sheet re-enters this method) and before any money moves.
    if (!rulesChecked) {
      final allowed = await TillGuardService.instance.review(
        context,
        lines: _guardLines(cart),
        cartDiscount: cart.manualDiscount,
        creditAmount: _selectedMethod == PaymentMethod.debt ? cart.total : 0,
        customerId: cart.customerId,
        customerName: cart.customerName,
      );
      if (!allowed || !mounted) return;
    }

    String? result;
    double cashChangeDue = 0;

    switch (_selectedMethod!) {
      case PaymentMethod.cash:
        // Ask what the customer handed over so the cashier sees the change to
        // give back; cancelling the sheet abandons the sale untouched.
        final tendered = await showCashTenderSheet(context, total: cart.total);
        if (tendered == null || !mounted) return;
        result = await paymentNotifier.processCashPayment(
          amount: cart.total,
          tenderedAmount: tendered,
          items: cart.items,
          customerId: cart.customerId,
          discountAmount: cart.discount,
          couponCode: _couponCodeFor(cart),
        );
        cashChangeDue = cashChange(total: cart.total, tendered: tendered);
        break;
      case PaymentMethod.mpesa:
        if (!_isKenyanPhone(_phoneController.text)) {
          final ready = await _showMpesaDetailsSheet(cart.total);
          if (!ready || !mounted) return;
          await _processPayment(rulesChecked: true);
          return;
        }
        result = await paymentNotifier.processMpesaPayment(
          amount: cart.total,
          phoneNumber: _normalizeKenyanPhone(_phoneController.text),
          discountAmount: cart.discount,
          items: cart.items,
          customerId: cart.customerId,
          couponCode: _couponCodeFor(cart),
        );
        break;
      case PaymentMethod.debt:
        // Whole sale is owed — requires a customer to record the debt
        // against. Prompt to pick one if none is set.
        if (cart.customerId == null) {
          if (mounted) {
            showGlassSnackBar(
              context,
              'Select a customer before selling on debt',
              icon: Icons.person_off_rounded,
              color: DesignColors.warning,
            );
          }
          return;
        }
        result = await paymentNotifier.processCreditPayment(
          amount: cart.total,
          items: cart.items,
          customerId: cart.customerId,
          customerName: cart.customerName,
          discountAmount: cart.discount,
          couponCode: _couponCodeFor(cart),
        );
        break;
      case PaymentMethod.split:
        final tenders = await _showSplitPaymentSheet(cart.total);
        if (tenders == null) return; // cancelled
        // A split with a debt (CREDIT) portion needs a customer to owe it.
        final hasDebt = tenders.any((t) => t.method == 'CREDIT');
        final tendered =
            tenders.fold<double>(0, (sum, tender) => sum + tender.amount);
        if (!hasDebt) {
          cashChangeDue = cashChange(total: cart.total, tendered: tendered);
        }
        if (hasDebt && cart.customerId == null) {
          final customer = await _showCustomerPicker();
          if (customer == null || !mounted) return;
          ref.read(cartProvider.notifier).setCustomer(
                customer.id,
                customerName: customer.name,
              );
          cart = ref.read(cartProvider);
        }
        // The debt part of a split is only known now, so check it here.
        final creditPart = tenders
            .where((t) => t.method == 'CREDIT')
            .fold<double>(0, (sum, t) => sum + t.amount);
        if (creditPart > 0) {
          if (!mounted) return;
          final allowedCredit = await TillGuardService.instance.review(
            context,
            lines: const [],
            creditAmount: creditPart,
            customerId: cart.customerId,
            customerName: cart.customerName,
            includePricing: false,
          );
          if (!allowedCredit || !mounted) return;
        }
        result = await paymentNotifier.processSplitPayment(
          amount: cart.total,
          items: cart.items,
          tenders: tenders,
          customerId: cart.customerId,
          discountAmount: cart.discount,
          couponCode: _couponCodeFor(cart),
        );
        break;
    }

    // Surface any error the payment notifier set (e.g. debt with no
    // customer, or a failed tender) instead of silently doing nothing.
    if (result == null) {
      final err = ref.read(paymentProvider).error;
      if (err != null && mounted) {
        if (_isPayoutError(err)) {
          await _refreshPayoutStatus();
          if (mounted) await _showPayoutNotReady();
        } else if (err.startsWith('An earlier M-Pesa payment is still open')) {
          await _showPendingMpesaPayment(err);
        } else {
          showGlassSnackBar(
            context,
            err,
            icon: Icons.error_outline_rounded,
            color: DesignColors.error,
          );
        }
      }
    }

    if (result != null && mounted) {
      final customerId = cart.customerId;
      var customerHistoryFailed = false;

      if (customerId != null) {
        try {
          await getIt<AppDatabase>()
              .recordCustomerPurchase(customerId, cart.total);
        } catch (_) {
          // The sale is already saved or provider-confirmed. A local customer
          // history counter must never strand the cashier on checkout and make
          // them think they should charge the customer again.
          customerHistoryFailed = true;
        }
      }

      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      // These FutureProviders retain their last result. Invalidate them so
      // the POS grid reflects the local stock decrement immediately.
      ref.invalidate(filteredProductsProvider);
      ref.invalidate(favoriteProductsProvider);
      context.go('/receipt/$result?fresh=1');
      if (customerHistoryFailed) {
        showGlassSnackBar(
          context,
          'Sale completed. Customer purchase history could not be updated.',
          icon: Icons.info_outline_rounded,
          color: DesignColors.warning,
        );
      }
      // Shown after navigating so the cashier still sees the change figure on
      // the receipt screen while handing the money back.
      if (cashChangeDue > 0) {
        showGlassSnackBar(
          context,
          'Give change: KES ${cashChangeDue.toStringAsFixed(cashChangeDue.truncateToDouble() == cashChangeDue ? 0 : 2)}',
          icon: Icons.payments_rounded,
          color: DesignColors.accent,
        );
      }
    }
  }

  Future<void> _showPendingMpesaPayment(String message) async {
    final openPayments = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.pending_actions_rounded),
        title: const Text('M-Pesa payment needs checking'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep cart'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Check payment'),
          ),
        ],
      ),
    );
    if (openPayments == true && mounted) {
      ref.read(paymentProvider.notifier).clearError();
      await context.push('/payments');
    }
  }

  /// Collects cash and debt tenders.
  /// that together must cover the sale total. Returns null if cancelled.
  Future<List<PaymentTender>?> _showSplitPaymentSheet(double total) async {
    final rows = <_TenderRow>[
      _TenderRow(method: 'CASH', amountController: TextEditingController()),
      _TenderRow(method: 'CREDIT', amountController: TextEditingController()),
    ];

    final confirmed = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final entered = rows.fold<double>(
              0,
              (sum, r) =>
                  sum + (double.tryParse(r.amountController.text) ?? 0));
          final remaining = total - entered;
          final remainingCents =
              (total * 100).round() - (entered * 100).round();
          final enteredRows = rows
              .where((r) => (double.tryParse(r.amountController.text) ?? 0) > 0)
              .length;
          final debtAmount = rows
              .where((r) => r.method == 'CREDIT')
              .fold<double>(
                  0,
                  (sum, r) =>
                      sum + (double.tryParse(r.amountController.text) ?? 0));
          final debtOverpaid = debtAmount > 0 && remainingCents < 0;
          final splitIncomplete = enteredRows < 2;
          final canConfirm =
              remainingCents <= 0 && !debtOverpaid && !splitIncomplete;
          final statusMessage = splitIncomplete
              ? 'Enter an amount for at least two tenders.'
              : debtOverpaid
                  ? 'A split with debt must add up exactly to the amount due.'
                  : remainingCents > 0
                      ? 'Remaining: KES ${remaining.toStringAsFixed(2)}'
                      : 'Fully covered'
                          '${remainingCents < 0 ? ' (change: KES ${(-remaining).toStringAsFixed(2)})' : ''}';

          return Padding(
            padding: EdgeInsets.fromLTRB(
                DesignSpacing.xl,
                DesignSpacing.xs,
                DesignSpacing.xl,
                DesignSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Split Payment',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: DesignSpacing.xs),
                Text('Total due: KES ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: isDark
                            ? DesignColors.darkTextSecondary
                            : DesignColors.textSecondary)),
                const SizedBox(height: DesignSpacing.lg),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                  child: SingleChildScrollView(
                    child: Column(
                      children: rows.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(
                              bottom: DesignSpacing.md - 2),
                          padding: const EdgeInsets.all(DesignSpacing.md),
                          decoration: BoxDecoration(
                            color: isDark
                                ? DesignColors.darkSurfaceElevated
                                : DesignColors.surfaceSubtle,
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: row.method,
                                      decoration: const InputDecoration(
                                          labelText: 'Method',
                                          border: InputBorder.none),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'CASH', child: Text('Cash')),
                                        DropdownMenuItem(
                                            value: 'CREDIT',
                                            child: Text('Debt (owed)')),
                                      ],
                                      onChanged: (v) => setSheetState(
                                          () => row.method = v ?? row.method),
                                    ),
                                  ),
                                  const SizedBox(width: DesignSpacing.md - 2),
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: row.amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                          labelText: 'Amount (KES)',
                                          border: InputBorder.none),
                                      onChanged: (_) => setSheetState(() {}),
                                    ),
                                  ),
                                  if (rows.length > 1)
                                    // 48px min hit target (default IconButton
                                    // constraints) with a Material ripple —
                                    // the raw icon was a sub-44 tap target
                                    // for a destructive action.
                                    IconButton(
                                      tooltip: 'Remove',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 48, minHeight: 48),
                                      onPressed: () => setSheetState(() {
                                        rows
                                            .removeAt(index)
                                            .amountController
                                            .dispose();
                                      }),
                                      icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          color: DesignColors.error),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setSheetState(() => rows.add(_TenderRow(
                      method: 'CASH',
                      amountController: TextEditingController()))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add another tender'),
                ),
                const SizedBox(height: DesignSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(DesignSpacing.md),
                  decoration: BoxDecoration(
                    color: (canConfirm
                            ? DesignColors.success
                            : DesignColors.warning)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                  ),
                  child: Text(
                    statusMessage,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: !canConfirm
                          ? DesignColors.warning
                          : DesignColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: DesignSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canConfirm
                        ? () => Navigator.pop(sheetContext, true)
                        : null,
                    child: const Text('Confirm Split'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true) {
      for (final row in rows) {
        row.amountController.dispose();
      }
      return null;
    }

    final tenders = rows
        .where((r) => (double.tryParse(r.amountController.text) ?? 0) > 0)
        .map((r) => PaymentTender(
              method: r.method,
              amount: double.parse(r.amountController.text),
            ))
        .toList();
    for (final row in rows) {
      row.amountController.dispose();
    }
    return tenders;
  }
}

class _CustomerChoice {
  const _CustomerChoice({required this.id, required this.name});

  final String id;
  final String name;
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet();

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _customers = const [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final customers = await getIt<AppDatabase>()
          .searchCustomers(_searchController.text.trim());
      if (!mounted || request != _request) return;
      setState(() {
        _customers = customers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _addCustomer() async {
    // The sale records today's credit after selection. Hiding the opening
    // balance control here prevents the same debt from being recorded twice.
    final added =
        await showAddCustomerSheet(context, allowInitialCredit: false);
    if (added == null || !mounted) return;
    Navigator.of(context).pop(_CustomerChoice(id: added.id, name: added.name));
  }

  void _choose(Map<String, dynamic> customer) {
    Navigator.of(context).pop(_CustomerChoice(
      id: customer['id'] as String,
      name: customer['name'] as String? ?? 'Customer',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = (screenHeight - keyboardHeight - DesignSpacing.xxl)
        .clamp(240.0, screenHeight)
        .toDouble();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignSpacing.lg,
        DesignSpacing.xs,
        DesignSpacing.lg,
        keyboardHeight + DesignSpacing.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Who is buying on credit?',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: DesignSpacing.xs),
            Text(
                'Choose an existing customer or add one. Your sale stays here.',
                style: TextStyle(color: secondary)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                setState(() {});
                _searchDebounce?.cancel();
                _searchDebounce =
                    Timer(const Duration(milliseconds: 220), _loadCustomers);
              },
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _loadCustomers();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: DesignSpacing.sm),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: DesignColors.accent))
                  : _failed
                      ? EmptyState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Customers could not load',
                          subtitle: 'Try again or add a customer to continue.',
                          actionLabel: 'Retry',
                          onAction: _loadCustomers,
                        )
                      : _customers.isEmpty
                          ? EmptyState(
                              icon: Icons.person_search_rounded,
                              title: 'No matching customers',
                              subtitle:
                                  'Add this customer and continue the sale.',
                              actionLabel: 'Add customer',
                              actionIcon: Icons.person_add_alt_1_rounded,
                              onAction: _addCustomer,
                            )
                          : ListView.separated(
                              itemCount: _customers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: DesignSpacing.xs),
                              itemBuilder: (context, index) {
                                final customer = _customers[index];
                                final name =
                                    customer['name'] as String? ?? 'Customer';
                                final phone =
                                    customer['phone'] as String? ?? '';
                                final balance =
                                    (customer['balance'] as num?)?.toDouble() ??
                                        0;
                                return Material(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(
                                      DesignSpacing.radiusMd),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          DesignSpacing.radiusMd),
                                      side: BorderSide(
                                        color: isDark
                                            ? DesignColors.darkBorder
                                            : DesignColors.surfaceBorder,
                                      ),
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: DesignColors.accent
                                          .withValues(alpha: 0.12),
                                      foregroundColor: DesignColors.accent,
                                      child: Text(name.isEmpty
                                          ? '?'
                                          : name[0].toUpperCase()),
                                    ),
                                    title: Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text([
                                      if (phone.isNotEmpty) phone,
                                      if (balance > 0)
                                        'Owes KES ${balance.toStringAsFixed(0)}',
                                    ].join(' · ')),
                                    trailing: const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: DesignColors.accent),
                                    onTap: () => _choose(customer),
                                  ),
                                );
                              },
                            ),
            ),
            const SizedBox(height: DesignSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addCustomer,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add a new customer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TenderRow {
  String method;
  final TextEditingController amountController;

  _TenderRow({required this.method, required this.amountController});
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DesignSpacing.md + 2),
      borderRadius: DesignSpacing.radiusMd + 2,
      blur: isSelected ? 12 : 4,
      tint: isSelected
          ? color.withValues(alpha: 0.08)
          : (isDark ? DesignColors.glassDark : DesignColors.glassWhite),
      borderColor: isSelected
          ? color.withValues(alpha: 0.4)
          : (isDark ? DesignColors.glassDarkBorder : DesignColors.glassBorder),
      boxShadow: isSelected
          ? [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      child: Row(
        children: [
          Container(
            width: DesignSpacing.xxl + 24,
            height: DesignSpacing.xxl + 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: DesignSpacing.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: DesignType.chatBody + 2,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? color
                        : (isDark
                            ? DesignColors.darkTextPrimary
                            : DesignColors.textPrimary),
                  ),
                ),
                const SizedBox(height: DesignSpacing.xs - 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: DesignType.chatBody - 1,
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 18),
            ),
        ],
      ),
    );
  }
}
