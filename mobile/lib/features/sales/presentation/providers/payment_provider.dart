import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart' hide CartItem;
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'cart_provider.dart';

const _uuid = Uuid();

/// One payment component of a split sale, e.g. { method: CASH, amount: 500 }.
/// Backend enum values (not the display-only [PaymentMethod] enum in
/// payment_screen.dart) — this must match what CreateSaleDto expects.
class PaymentTender {
  final String method; // 'CASH' | 'CREDIT'
  final double amount;
  final String? reference;

  const PaymentTender(
      {required this.method, required this.amount, this.reference});

  Map<String, dynamic> toJson() => {
        'method': method,
        'amount': amount,
        if (reference != null) 'reference': reference,
      };

  static PaymentTender fromJson(Map<String, dynamic> json) => PaymentTender(
        method: json['method'] as String,
        amount: (json['amount'] as num).toDouble(),
        reference: json['reference'] as String?,
      );
}

/// A sale-wide discount and the coupon behind it, carried alongside the
/// payment so the server records both (and not just a lower total).
class _SaleExtras {
  const _SaleExtras([this.discountAmount = 0, this.couponCode]);

  final double discountAmount;
  final String? couponCode;
}

// Payment state
class PaymentState {
  final bool isProcessing;
  final String? error;
  final String? currentTransactionId;

  const PaymentState({
    this.isProcessing = false,
    this.error,
    this.currentTransactionId,
  });

  PaymentState copyWith({
    bool? isProcessing,
    String? error,
    String? currentTransactionId,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      currentTransactionId: currentTransactionId ?? this.currentTransactionId,
    );
  }
}

class PaymentNotifier extends StateNotifier<PaymentState> {
  final ApiClient _apiClient;
  final AppDatabase _database;
  final SyncService _syncService;
  final AuthService _authService;
  final ConnectivityService _connectivity;
  String? _pendingMpesaFingerprint;
  String? _pendingMpesaRequestId;
  String? _pendingLocalSaleId;
  int _sessionGeneration = 0;

  PaymentNotifier({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncService syncService,
    required AuthService authService,
    required ConnectivityService connectivity,
  })  : _apiClient = apiClient,
        _database = database,
        _syncService = syncService,
        _authService = authService,
        _connectivity = connectivity,
        super(const PaymentState());

  bool get hasUnresolvedMerchantPayment => _pendingMpesaRequestId != null;

  /// True when a payment-hub status check belongs to the checkout currently
  /// held open by this notifier. The checkout must keep its reference until
  /// it writes the verified receipt and clears the cart.
  bool isActiveMerchantCheckout(String reference) =>
      _pendingMpesaRequestId != null && state.currentTransactionId == reference;

  /// Payment UI state belongs to one cashier, shop, and branch. Invalidates
  /// async completions too, so a late provider response cannot write a sale
  /// into whichever account signed in next.
  void resetForSession() {
    _sessionGeneration++;
    _pendingMpesaFingerprint = null;
    _pendingMpesaRequestId = null;
    _pendingLocalSaleId = null;
    state = const PaymentState();
  }

  bool _isCurrentSession(int generation) => generation == _sessionGeneration;

  /// Payment methods can be triggered from more than one UI surface. Keep the
  /// transaction lock here as well as in the screen so a fast double tap or a
  /// second caller cannot create another sale while the first is being saved.
  /// A pending provider charge also locks cash, credit, and split until its
  /// reference is resolved; only an M-Pesa retry may reuse that request.
  bool _blockPaymentStart({bool allowPendingMerchantRetry = false}) {
    if (state.isProcessing) return true;
    if (!allowPendingMerchantRetry && _pendingMpesaRequestId != null) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'An earlier M-Pesa payment is still open. Check it before taking another payment.',
      );
      return true;
    }
    return false;
  }

  void acknowledgeMerchantPayment(String reference, String status) {
    if (state.currentTransactionId != reference) return;
    if (status == 'COMPLETED') {
      // Keep the reference locked to checkout until it persists the receipt
      // and clears the cart. The payment hub can confirm provider status, but
      // it must not turn the same cart back into a fresh charge action.
      state = state.copyWith(
        isProcessing: false,
        error: null,
      );
      return;
    }
    if (status != 'FAILED') return;
    _pendingLocalSaleId = null;
    _pendingMpesaFingerprint = null;
    _pendingMpesaRequestId = null;
    state = const PaymentState();
  }

  Future<String?> processCashPayment({
    required double amount,
    required double tenderedAmount,
    required List<CartItem> items,
    String? customerId,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    if (_blockPaymentStart()) return null;
    final sessionGeneration = _sessionGeneration;
    state = state.copyWith(isProcessing: true, error: null);

    if (!amount.isFinite ||
        !tenderedAmount.isFinite ||
        amount <= 0 ||
        (tenderedAmount * 100).round() < (amount * 100).round()) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Cash received must cover the sale total.',
      );
      return null;
    }

    try {
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';

      // Create sale locally first
      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'CASH',
        total: amount,
        discountAmount: discountAmount,
        customerId: customerId,
      );
      if (!_isCurrentSession(sessionGeneration)) return null;

      await _syncOrQueueSale(
        saleId,
        items,
        'CASH',
        tenderedAmount,
        null,
        null,
        customerId,
        _SaleExtras(discountAmount, couponCode),
      );
      if (!_isCurrentSession(sessionGeneration)) return null;

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      if (!_isCurrentSession(sessionGeneration)) return null;
      state = state.copyWith(isProcessing: false, error: _paymentError(e));
      return null;
    }
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(error: null);
  }

  Future<String?> processMpesaPayment({
    required double amount,
    required String phoneNumber,
    required double discountAmount,
    required List<CartItem> items,
    String? customerId,
    String? couponCode,
  }) async {
    if (_blockPaymentStart(allowPendingMerchantRetry: true)) return null;
    final sessionGeneration = _sessionGeneration;
    final previousReference = state.currentTransactionId;
    state = state.copyWith(isProcessing: true, error: null);

    if (!_connectivity.isOnline) {
      state = state.copyWith(
        isProcessing: false,
        error: 'M-Pesa payments require internet connection',
      );
      return null;
    }

    try {
      // Format phone number
      String formattedPhone = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (formattedPhone.startsWith('0')) {
        formattedPhone = '254${formattedPhone.substring(1)}';
      } else if (!formattedPhone.startsWith('254')) {
        formattedPhone = '254$formattedPhone';
      }

      final fingerprint = jsonEncode({
        'amount': amount,
        'discount': discountAmount,
        'couponCode': couponCode,
        'phone': formattedPhone,
        'customerId': customerId,
        'items': items.map((item) => item.toJson()).toList(),
      });
      if (_pendingMpesaRequestId != null &&
          _pendingMpesaFingerprint != fingerprint) {
        state = state.copyWith(
            isProcessing: false,
            error:
                'An earlier M-Pesa payment is still open. Check it in Payments before changing the cart.');
        return null;
      }

      // The server prices the cart, charges through the shop's Paystack
      // subaccount, verifies the charge, and creates the receipt. The old
      // host Jenga endpoint settled into Counterbase's own account.
      var saleId = _pendingLocalSaleId ?? _uuid.v4();
      final requestId = _pendingMpesaRequestId ?? _uuid.v4();
      String? reference = previousReference;
      if (reference == null) {
        _pendingLocalSaleId = saleId;
        _pendingMpesaRequestId = requestId;
        _pendingMpesaFingerprint = fingerprint;
        final response = await _apiClient.startMerchantMpesaPayment({
          'requestId': requestId,
          'phoneNumber': formattedPhone,
          'sale': {
            'branchId': _authService.branchId,
            if (_authService.deviceId != null)
              'deviceId': _authService.deviceId,
            if (customerId != null) 'customerId': customerId,
            'items': items
                .map((item) => {
                      'productId': item.productId,
                      'quantity': item.quantity,
                      'unitPrice': item.unitPrice,
                      'discount': item.discount,
                      if (item.saleUnit != null) 'unit': item.saleUnit,
                      if (item.unitConversionFactor != null)
                        'quantityPerUnit': item.unitConversionFactor,
                    })
                .toList(),
            'discountAmount': discountAmount,
            if (couponCode != null) 'couponCode': couponCode,
            'paymentMethod': 'MPESA',
            'paidAmount': amount,
          },
        });
        if (!_isCurrentSession(sessionGeneration)) return null;
        reference = response['reference']?.toString();
      }
      if (reference == null || reference.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          error:
              'The payment provider did not return a reference. Check the customer phone before retrying.',
        );
        return null;
      }
      // The backend stores a verified M-Pesa sale under this same offlineId.
      // Using it locally lets a server pull reconcile the sale even if the app
      // closes between Paystack confirmation and the local sync flag update.
      saleId = 'paystack-$reference';
      _pendingLocalSaleId = saleId;
      _pendingMpesaFingerprint = fingerprint;
      state = state.copyWith(currentTransactionId: reference);
      final verified = await _pollMerchantMpesaStatus(reference);
      if (!_isCurrentSession(sessionGeneration)) return null;
      if (verified == null || verified['status'] != 'COMPLETED') {
        final status = verified?['status']?.toString() ?? 'PENDING';
        final message = status == 'FAILED'
            ? 'M-Pesa payment failed. Reference: $reference'
            : status == 'NEEDS_REVIEW'
                ? 'Payment was received but the receipt needs review. Give support reference $reference. Do not charge again.'
                : 'Payment is still pending. Press Check M-Pesa Payment to check this reference without a second charge: $reference.';
        if (status == 'FAILED') {
          _pendingLocalSaleId = null;
          _pendingMpesaFingerprint = null;
          _pendingMpesaRequestId = null;
          state = PaymentState(error: message);
        } else {
          state = state.copyWith(isProcessing: false, error: message);
        }
        return null;
      }

      final receiptNumber = verified['receiptNumber']?.toString() ?? reference;
      final verifiedAmount = (verified['amount'] as num?)?.toDouble() ?? amount;
      final quotedSubtotal = items.fold<double>(
        0,
        (sum, item) => sum + item.total,
      );
      final verifiedTax = roundCurrency(
        verifiedAmount - (quotedSubtotal - discountAmount),
      );
      var localSale = await _database.getPendingSaleById(saleId);
      localSale ??= await _database.getMerchantMpesaSaleByReference(reference);
      if (!_isCurrentSession(sessionGeneration)) return null;
      final localSaleId = localSale?.id ?? saleId;
      if (localSale == null) {
        await _createLocalSale(
          saleId: localSaleId,
          receiptNumber: receiptNumber,
          items: items,
          paymentMethod: 'MPESA',
          total: verifiedAmount,
          discountAmount: discountAmount,
          taxAmountOverride: verifiedTax,
          paymentReference: reference,
          customerId: customerId,
        );
        if (!_isCurrentSession(sessionGeneration)) return null;
      } else {
        await _database.updateSaleReceiptNumber(localSaleId, receiptNumber);
        if (!_isCurrentSession(sessionGeneration)) return null;
      }
      await _database.markSaleAsSynced(localSaleId);
      if (!_isCurrentSession(sessionGeneration)) return null;
      // Paystack has verified the charge and the canonical receipt is saved.
      // Pulling unrelated remote changes can paginate for minutes, so let the
      // cashier return to the receipt while the background sync catches up.
      unawaited(_syncService.pullChanges());
      if (!_isCurrentSession(sessionGeneration)) return null;

      _pendingLocalSaleId = null;
      _pendingMpesaFingerprint = null;
      _pendingMpesaRequestId = null;
      state = const PaymentState();
      return localSaleId;
    } catch (e) {
      if (!_isCurrentSession(sessionGeneration)) return null;
      // Validation and authorization errors happen before the provider is
      // prompted. Network and server errors keep the idempotency key so a
      // retry can recover the original reference instead of charging twice.
      if (state.currentTransactionId == null &&
          e is DioException &&
          [400, 401, 403, 404, 409, 422].contains(e.response?.statusCode)) {
        _pendingLocalSaleId = null;
        _pendingMpesaFingerprint = null;
        _pendingMpesaRequestId = null;
      }
      state = state.copyWith(
          isProcessing: false,
          error: state.currentTransactionId == null
              ? _paymentError(e)
              : 'Payment reference ${state.currentTransactionId} must be checked before retrying. No new charge will be sent.');
      return null;
    }
  }

  Future<String?> processCreditPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
    String? customerName,
    String? notes,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    if (_blockPaymentStart()) return null;
    final sessionGeneration = _sessionGeneration;
    state = state.copyWith(isProcessing: true, error: null);

    // A credit (debt) sale must be attributable to a customer — otherwise
    // there's no one to record the debt against and no way to collect it.
    if (customerId == null) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Select a customer before selling on debt',
      );
      return null;
    }

    try {
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';

      // Create sale locally first
      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'CREDIT',
        total: amount,
        discountAmount: discountAmount,
        customerBalanceDelta: amount,
        paymentReference: customerId,
        customerId: customerId,
      );
      if (!_isCurrentSession(sessionGeneration)) return null;

      await _syncOrQueueSale(
        saleId,
        items,
        'CREDIT',
        0,
        customerId,
        null,
        customerId,
        _SaleExtras(discountAmount, couponCode),
      );
      if (!_isCurrentSession(sessionGeneration)) return null;

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      if (!_isCurrentSession(sessionGeneration)) return null;
      state = state.copyWith(isProcessing: false, error: _paymentError(e));
      return null;
    }
  }

  /// Records one sale paid via multiple tenders at once (part cash and debt).
  /// [tenders] must cover [amount] and include at least two positive amounts.
  /// A split containing debt must equal the total exactly so change cannot be
  /// mistaken for additional customer debt.
  Future<String?> processSplitPayment({
    required double amount,
    required List<CartItem> items,
    required List<PaymentTender> tenders,
    String? customerId,
    double discountAmount = 0,
    String? couponCode,
  }) async {
    if (_blockPaymentStart()) return null;
    final sessionGeneration = _sessionGeneration;
    state = state.copyWith(isProcessing: true, error: null);

    if (tenders.any((tender) => tender.method == 'MPESA')) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'Use a separate M-Pesa sale for provider-verified shop payouts. Split M-Pesa is not available yet.',
      );
      return null;
    }

    final cashTenders = tenders.where((tender) => tender.method == 'CASH');
    final debtTenders = tenders.where((tender) => tender.method == 'CREDIT');
    if (tenders.length != 2 ||
        cashTenders.length != 1 ||
        debtTenders.length != 1 ||
        tenders.any((tender) =>
            !{'CASH', 'CREDIT'}.contains(tender.method) ||
            !tender.amount.isFinite ||
            tender.amount <= 0)) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'A split needs one positive cash amount and one positive debt amount.',
      );
      return null;
    }

    final tenderTotal = tenders.fold<double>(0, (sum, t) => sum + t.amount);
    const maxSafeCurrencyAmount = 90071992547409.9;
    if (!tenderTotal.isFinite ||
        tenderTotal > maxSafeCurrencyAmount ||
        amount > maxSafeCurrencyAmount) {
      state = state.copyWith(
        isProcessing: false,
        error: 'The split amounts are too large. Check them and try again.',
      );
      return null;
    }
    if ((tenderTotal * 100).round() != (amount * 100).round()) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Cash and debt must add up exactly to the sale total.',
      );
      return null;
    }

    final debtPortion = debtTenders.single.amount;
    if (debtPortion > 0 && customerId == null) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Select a customer before adding a debt portion',
      );
      return null;
    }

    try {
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';

      // Tenders are stored as JSON in paymentReference — SPLIT is the only
      // payment method whose "reference" is structured data rather than a
      // single external transaction id, reusing the field rather than
      // adding a dedicated column/migration for what's still a single
      // nullable string slot everywhere else.
      final tendersJson = jsonEncode(tenders.map((t) => t.toJson()).toList());

      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'SPLIT',
        total: amount,
        discountAmount: discountAmount,
        customerBalanceDelta: debtPortion,
        paymentReference: tendersJson,
        customerId: customerId,
      );
      if (!_isCurrentSession(sessionGeneration)) return null;

      await _syncOrQueueSale(saleId, items, 'SPLIT', amount, tendersJson,
          tenders, customerId, _SaleExtras(discountAmount, couponCode));
      if (!_isCurrentSession(sessionGeneration)) return null;

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      if (!_isCurrentSession(sessionGeneration)) return null;
      state = state.copyWith(isProcessing: false, error: _paymentError(e));
      return null;
    }
  }

  Future<void> _createLocalSale({
    required String saleId,
    required String receiptNumber,
    required List<CartItem> items,
    required String paymentMethod,
    required double total,
    double discountAmount = 0,
    double? taxAmountOverride,
    double customerBalanceDelta = 0,
    String? paymentReference,
    String? customerId,
  }) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    // Cash, credit and split receipts use the business rate shown in the cart.
    // Verified M-Pesa passes tax derived from the server-confirmed charge
    // amount, so a settings change while the customer approves the prompt
    // cannot make the local receipt disagree with the settled sale.
    final tax = taxAmountOverride == null
        ? roundCurrency(
            (subtotal - discountAmount) * (_authService.taxRatePercent / 100),
          )
        : roundCurrency(taxAmountOverride);

    // Create pending sale in local database
    await _database.createPendingSale(
      PendingSalesCompanion.insert(
        id: saleId,
        receiptNumber: receiptNumber,
        subtotal: subtotal,
        discount: Value(discountAmount),
        tax: Value(tax),
        total: total,
        paymentMethod: paymentMethod,
        paymentReference: Value(paymentReference),
        customerId: Value(customerId),
        cashierId: _authService.userId!,
        branchId: _authService.branchId!,
        status: const Value('COMPLETED'),
        createdAt: DateTime.now(),
      ),
      items
          .map((item) => PendingSaleItemsCompanion.insert(
                saleId: saleId,
                productId: item.productId,
                productName: item.productName,
                sku: item.sku,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                total: item.total,
                // Capture the tier this line was sold at so the receipt can
                // show "1 box @ 1,200 (12 pcs @ 100/pc)". saleUnit is the sold
                // unit label; unitConversionFactor is base units per sold unit.
                unit: Value(item.saleUnit),
                quantityPerUnit: Value(item.unitConversionFactor),
              ))
          .toList(),
      customerBalanceDelta: customerBalanceDelta,
      decrementLocalStock: true,
    );
  }

  Future<void> _syncOrQueueSale(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double paidAmount, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
    _SaleExtras extras = const _SaleExtras(),
  ]) async {
    final sessionGeneration = _sessionGeneration;
    // The sale and stock deduction are already committed locally. Persist its
    // outbox event before returning, then let the normal sync worker upload it
    // without holding checkout on API timeouts or unrelated queued events.
    await _tryQueueSaleForSync(
      saleId,
      items,
      paymentMethod,
      paidAmount,
      paymentReference,
      tenders,
      customerId,
      extras,
    );
    if (!_isCurrentSession(sessionGeneration) || !_connectivity.isOnline) {
      return;
    }

    // The outbox is durable now. A server delay or outage must not block the
    // cashier from seeing the locally saved receipt; the periodic worker will
    // retry if this background attempt fails.
    unawaited(_syncService.syncPendingEvents());
  }

  /// A local sale is committed before this sync attempt. If both network sync
  /// and queue persistence fail, keep the valid local receipt successful so a
  /// cashier isn't prompted to ring up the same sale again. The sync recovery
  /// sweep can re-enqueue any remaining unsynced sale later.
  Future<void> _tryQueueSaleForSync(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double paidAmount,
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
    _SaleExtras extras,
  ) async {
    try {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        paidAmount,
        paymentReference,
        tenders,
        customerId,
        extras,
      );
    } catch (_) {
      // Recovery uses pending_sales.is_synced=false as its source of truth.
    }
  }

  Future<void> _queueSaleForSync(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double paidAmount, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
    _SaleExtras extras = const _SaleExtras(),
  ]) async {
    await _syncService.queueSyncItem(
      tableName: 'sales',
      recordId: saleId,
      action: SyncAction.create,
      eventType: SyncEventType.saleCreated,
      data: {
        'offlineId': saleId,
        // branchId is required server-side; a queued sale that omits it
        // would keep failing forever when the background sync retries it.
        if (_authService.branchId != null) 'branchId': _authService.branchId,
        if (_authService.deviceId != null) 'deviceId': _authService.deviceId,
        if (customerId != null) 'customerId': customerId,
        // Match the live sales DTO shape. CartItem.toJson is optimized for
        // local persistence and uses saleUnit/unitConversionFactor, while the
        // sync handler expects unit/quantityPerUnit just like createSale.
        'items': items
            .map((item) => {
                  'productId': item.productId,
                  'quantity': item.quantity,
                  'unitPrice': item.unitPrice,
                  'discount': item.discount,
                  if (item.saleUnit != null) 'unit': item.saleUnit,
                  if (item.unitConversionFactor != null)
                    'quantityPerUnit': item.unitConversionFactor,
                })
            .toList(),
        'paymentMethod': paymentMethod,
        'paymentReference': paymentReference,
        if (extras.discountAmount > 0) 'discountAmount': extras.discountAmount,
        if (extras.couponCode != null) 'couponCode': extras.couponCode,
        'paidAmount': paidAmount,
        // Offline sales must retain the tax rate the cashier saw in the cart;
        // a settings change before sync must not rewrite an already-paid sale.
        'taxRatePercentSnapshot': _authService.taxRatePercent,
        'cashierId': _authService.userId,
        if (tenders != null) 'tenders': tenders.map((t) => t.toJson()).toList(),
      },
      deviceId: _authService.deviceId!,
      userId: _authService.userId ?? '',
      syncImmediately: false,
    );
  }

  Future<Map<String, dynamic>?> _pollMerchantMpesaStatus(
      String reference) async {
    // Paystack recommends waiting at least 10 seconds before checking an
    // asynchronous M-Pesa charge. A long 60-second wait kept the only checkout
    // button disabled; this brief wait respects the provider window, then lets
    // the cashier safely check this same reference again without a new charge.
    await Future<void>.delayed(const Duration(seconds: 10));
    try {
      final status = await _apiClient.getMerchantMpesaStatus(reference);
      if (['COMPLETED', 'FAILED', 'NEEDS_REVIEW'].contains(status['status'])) {
        return status;
      }
      return status;
    } catch (_) {
      // Network interruption is not proof of failure or a reason to charge again.
      return null;
    }
  }

  String _paymentError(Object error) {
    return apiErrorMessage(error);
  }
}

// Provider
final paymentProvider =
    StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  final notifier = PaymentNotifier(
    apiClient: getIt<ApiClient>(),
    database: getIt<AppDatabase>(),
    syncService: getIt<SyncService>(),
    authService: getIt<AuthService>(),
    connectivity: getIt<ConnectivityService>(),
  );
  ref.listen(
    authControllerProvider.select((auth) => auth.isAuthenticated
        ? (
            auth.user?['tenantId']?.toString(),
            auth.user?['branchId']?.toString(),
            auth.user?['id']?.toString(),
          )
        : (null, null, null)),
    (previous, next) {
      if (previous != null && previous != next) {
        notifier.resetForSession();
      }
    },
  );
  return notifier;
});
