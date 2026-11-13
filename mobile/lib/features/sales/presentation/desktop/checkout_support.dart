import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/auth/app_roles.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/till_guard.dart';
import '../../../../core/utils/format.dart' show roundCurrency;
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../accountability/data/till_guard_service.dart';
import '../../domain/cash_tender.dart';
import '../../domain/recorded_payment.dart';
import '../providers/cart_provider.dart';
import '../providers/catalog_provider.dart';
import '../providers/payment_provider.dart';
import '../widgets/record_payment_sheet.dart' show ApproverCheck;

// ─── Helpers shared by the phone payment screen and the desktop till ───

/// "0712 345 678", "+254712345678" and "712345678" all become 254712345678.
String normalizeKenyanPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.startsWith('254')) {
    digits = digits.substring(3);
  }
  return '254$digits';
}

bool isKenyanPhone(String value) {
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

/// The cart as the shop's price and discount rules see it. A coupon's share of
/// each line lowers the price the item really sold at, so a coupon cannot hide
/// a sale below cost, but it is the owner's own approved discount and does not
/// count against the cashier's limit.
List<GuardLine> guardLinesFor(CartState cart) {
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

/// Manual cart-level and per-line price reductions require sales.discount.
/// Coupon shares remain excluded because they are owner-approved discounts.
bool cartHasManualDiscount(CartState cart) =>
    cart.manualDiscount > 0 || cart.items.any((item) => item.discount > 0);

/// The coupon code to record with the sale, only if it actually took money off.
String? couponCodeFor(CartState cart) =>
    cart.couponDiscount > 0 ? cart.coupon?.code : null;

/// The shop's rules for payments it records itself, from local settings. A
/// damaged setting falls back to the safe defaults.
RecordedPaymentRules loadStoredRecordedRules() {
  final json = getIt<StorageService>().getRecordedPaymentRulesJson();
  if (json == null || json.isEmpty) return const RecordedPaymentRules();
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) {
      return RecordedPaymentRules.fromJson(decoded);
    }
  } catch (_) {
    // fall through to the defaults
  }
  return const RecordedPaymentRules();
}

/// The signed-in person's name, saved with every recorded payment.
String currentRecorderName() {
  final user = getIt<AuthService>().currentUser;
  final name = (user?['name'] ??
          '${user?['firstName'] ?? ''} ${user?['lastName'] ?? ''}')
      .toString()
      .trim();
  return name.isEmpty ? 'Cashier' : name;
}

/// Adds the sale to the customer's purchase history (connected shops only).
/// Returns true when that could not be written: the sale itself is already
/// saved, so the caller only mentions it.
Future<bool> recordSaleCustomerPurchase(CartState cart) async {
  final customerId = cart.customerId;
  if (customerId == null || getIt<AuthService>().isLocalWorkspace) {
    return false;
  }
  try {
    await getIt<AppDatabase>().recordCustomerPurchase(customerId, cart.total);
    return false;
  } catch (_) {
    // A local counter must never strand the cashier on checkout and make them
    // think they should charge the customer again.
    return true;
  }
}

// ─── Everything the desktop checkout needs from the outside world ───

/// The services the desktop till reads (auth, storage, API, database, till
/// rules). One seam, so a test can feed sample data without GetIt.
abstract class SellCheckoutHost {
  bool get isLocalWorkspace;
  RecordedPaymentRules get recordedRules;
  String get recorderId;
  String get recorderName;
  ApproverCheck get approverForPin;

  /// The merchant payout account; throws when it cannot be read.
  Future<Map<String, dynamic>?> loadPayoutAccount();
  Future<String?> customerPhone(String customerId);
  Future<List<Map<String, dynamic>>> searchCustomers(String query);

  /// The shop's price, discount and credit rules. May show its own dialog.
  /// True when the sale may go ahead.
  Future<bool> reviewSale(
    BuildContext context, {
    required List<GuardLine> lines,
    double cartDiscount = 0,
    double creditAmount = 0,
    String? customerId,
    String? customerName,
    bool includePricing = true,
  });

  Future<bool> recordCustomerPurchase(CartState cart);
}

class GetItSellCheckoutHost implements SellCheckoutHost {
  const GetItSellCheckoutHost();

  bool get _canViewCustomers => RolePermissions(
        getIt<AuthService>().currentUser?['permissions'] as List<dynamic>?,
      ).canSeeCustomers;

  @override
  bool get isLocalWorkspace => getIt<AuthService>().isLocalWorkspace;

  @override
  RecordedPaymentRules get recordedRules => loadStoredRecordedRules();

  @override
  String get recorderId => getIt<AuthService>().userId ?? '';

  @override
  String get recorderName => currentRecorderName();

  @override
  ApproverCheck get approverForPin => getIt<AuthService>().approverForPin;

  @override
  Future<Map<String, dynamic>?> loadPayoutAccount() =>
      getIt<ApiClient>().getMerchantPayoutAccount();

  @override
  Future<String?> customerPhone(String customerId) async {
    if (!_canViewCustomers) return null;
    final customer = await getIt<AppDatabase>().getCustomer(customerId);
    return customer?['phone'] as String?;
  }

  @override
  Future<List<Map<String, dynamic>>> searchCustomers(String query) =>
      _canViewCustomers
          ? getIt<AppDatabase>().searchCustomers(query)
          : Future.value(const []);

  @override
  Future<bool> reviewSale(
    BuildContext context, {
    required List<GuardLine> lines,
    double cartDiscount = 0,
    double creditAmount = 0,
    String? customerId,
    String? customerName,
    bool includePricing = true,
  }) =>
      TillGuardService.instance.review(
        context,
        lines: lines,
        cartDiscount: cartDiscount,
        creditAmount: creditAmount,
        customerId: customerId,
        customerName: customerName,
        includePricing: includePricing,
      );

  @override
  Future<bool> recordCustomerPurchase(CartState cart) =>
      recordSaleCustomerPurchase(cart);
}

final sellCheckoutHostProvider =
    Provider<SellCheckoutHost>((ref) => const GetItSellCheckoutHost());

// ─── The desktop checkout ───

/// How a customer paid, as the desktop payment panel names it.
enum SellTender { cash, mpesa, recordedMpesa, recordedBank, credit, split }

/// A line whose stock changed since it was added.
class StockIssue {
  const StockIssue(this.name, this.requested, this.available, this.message);
  final String name;
  final double requested;
  final double? available;
  final String message;
}

enum CheckoutStatus { sold, stopped, failed }

class CheckoutResult {
  const CheckoutResult._(
    this.status, {
    this.saleId,
    this.changeDue = 0,
    this.customerHistoryFailed = false,
    this.message,
    this.stockIssues = const [],
  });

  const CheckoutResult.sold(
    String saleId, {
    double changeDue = 0,
    bool customerHistoryFailed = false,
  }) : this._(
          CheckoutStatus.sold,
          saleId: saleId,
          changeDue: changeDue,
          customerHistoryFailed: customerHistoryFailed,
        );

  /// Nothing was charged and nothing is wrong: the cashier cancelled or the
  /// shop's rules asked for a change.
  const CheckoutResult.stopped([String? message])
      : this._(CheckoutStatus.stopped, message: message);

  const CheckoutResult.stock(List<StockIssue> issues)
      : this._(CheckoutStatus.stopped, stockIssues: issues);

  const CheckoutResult.failed(String message)
      : this._(CheckoutStatus.failed, message: message);

  final CheckoutStatus status;
  final String? saleId;
  final double changeDue;
  final bool customerHistoryFailed;
  final String? message;
  final List<StockIssue> stockIssues;
}

/// Runs a sale through the same steps as the phone's payment screen: stock
/// check, the shop's till rules, the payment notifier, then bookkeeping. The
/// money and sale logic stays in [PaymentNotifier]; this only orders the calls
/// and reports back without any sheet or navigation.
class DesktopCheckout {
  DesktopCheckout(this.ref);

  final WidgetRef ref;

  SellCheckoutHost get _host => ref.read(sellCheckoutHostProvider);

  Future<CheckoutResult> pay(
    BuildContext context,
    SellTender tender, {
    double cashReceived = 0,
    String phone = '',
    double splitCash = 0,
    RecordedPaymentDetails? recorded,
  }) async {
    final notifier = ref.read(paymentProvider.notifier);
    if (_host.isLocalWorkspace && tender == SellTender.mpesa) {
      return const CheckoutResult.failed(
        'M-Pesa requests are not available in this device-only checkout. Choose cash, customer credit or split payment.',
      );
    }
    if (notifier.hasUnresolvedMerchantPayment && tender != SellTender.mpesa) {
      return const CheckoutResult.stopped(
        'Check the pending M-Pesa payment before taking another method.',
      );
    }
    var cart = ref.read(cartProvider);
    if (cart.items.isEmpty) return const CheckoutResult.stopped();
    if (cartHasManualDiscount(cart) &&
        !ref.read(permissionsProvider).canApplyDiscount) {
      return const CheckoutResult.failed(
        'You do not have permission to apply discounts.',
      );
    }
    if ((tender == SellTender.credit || tender == SellTender.split) &&
        cart.customerId == null) {
      return const CheckoutResult.stopped('Choose a customer first.');
    }

    // Stock can change while an item sits in the cart.
    final checks = await ref.read(cartProvider.notifier).validateCartStock();
    final bad = checks.where((c) => c['available'] != true).toList();
    if (bad.isNotEmpty) {
      return CheckoutResult.stock([
        for (final c in bad)
          StockIssue(
            c['productName']?.toString() ?? 'Item',
            (c['requestedQuantity'] as num?)?.toDouble() ?? 0,
            (c['currentStock'] as num?)?.toDouble(),
            c['message']?.toString() ?? 'Stock unavailable',
          ),
      ]);
    }
    if (!context.mounted) return const CheckoutResult.stopped();
    cart = ref.read(cartProvider);

    final allowed = await _host.reviewSale(
      context,
      lines: guardLinesFor(cart),
      cartDiscount: cart.manualDiscount,
      creditAmount: tender == SellTender.credit ? cart.total : 0,
      customerId: cart.customerId,
      customerName: cart.customerName,
    );
    if (!allowed) return const CheckoutResult.stopped();

    String? saleId;
    var changeDue = 0.0;
    switch (tender) {
      case SellTender.cash:
        saleId = await notifier.processCashPayment(
          amount: cart.total,
          tenderedAmount: cashReceived,
          items: cart.items,
          customerId: cart.customerId,
          discountAmount: cart.discount,
          couponCode: couponCodeFor(cart),
        );
        changeDue = cashChange(total: cart.total, tendered: cashReceived);
      case SellTender.mpesa:
        saleId = await notifier.processMpesaPayment(
          amount: cart.total,
          phoneNumber: normalizeKenyanPhone(phone),
          discountAmount: cart.discount,
          items: cart.items,
          customerId: cart.customerId,
          couponCode: couponCodeFor(cart),
        );
      case SellTender.recordedMpesa:
      case SellTender.recordedBank:
        if (recorded == null) return const CheckoutResult.stopped();
        saleId = await notifier.processRecordedPayment(
          amount: cart.total,
          items: cart.items,
          details: recorded,
          customerId: cart.customerId,
          discountAmount: cart.discount,
        );
      case SellTender.credit:
        saleId = await notifier.processCreditPayment(
          amount: cart.total,
          items: cart.items,
          customerId: cart.customerId,
          customerName: cart.customerName,
          discountAmount: cart.discount,
          couponCode: couponCodeFor(cart),
        );
      case SellTender.split:
        final credit = roundCurrency(cart.total - splitCash);
        if (splitCash <= 0 || credit <= 0) {
          return const CheckoutResult.stopped(
            'A split needs some cash and some credit.',
          );
        }
        if (!context.mounted) return const CheckoutResult.stopped();
        final allowedCredit = await _host.reviewSale(
          context,
          lines: const [],
          creditAmount: credit,
          customerId: cart.customerId,
          customerName: cart.customerName,
          includePricing: false,
        );
        if (!allowedCredit) return const CheckoutResult.stopped();
        saleId = await notifier.processSplitPayment(
          amount: cart.total,
          items: cart.items,
          tenders: [
            PaymentTender(method: 'CASH', amount: splitCash),
            PaymentTender(method: 'CREDIT', amount: credit),
          ],
          customerId: cart.customerId,
          discountAmount: cart.discount,
          couponCode: couponCodeFor(cart),
        );
    }

    if (saleId == null) {
      final error = ref.read(paymentProvider).error;
      return CheckoutResult.failed(
        error ?? 'The sale could not be saved. Try again.',
      );
    }
    final historyFailed = await _host.recordCustomerPurchase(cart);
    ref.read(cartProvider.notifier).clear();
    // These providers keep their last result; refresh so the grid shows the
    // stock that was just sold.
    ref.invalidate(filteredProductsProvider);
    ref.invalidate(favoriteProductsProvider);
    return CheckoutResult.sold(
      saleId,
      changeDue: changeDue,
      customerHistoryFailed: historyFailed,
    );
  }
}
