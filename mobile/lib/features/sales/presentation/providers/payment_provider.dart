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

  void acknowledgeMerchantPayment(String reference, String status) {
    if (state.currentTransactionId != reference ||
        (status != 'COMPLETED' && status != 'FAILED')) {
      return;
    }
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

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
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
      final saleId = _pendingLocalSaleId ?? _uuid.v4();
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
      _pendingLocalSaleId = saleId;
      _pendingMpesaFingerprint = fingerprint;
      state = state.copyWith(currentTransactionId: reference);
      final verified = await _pollMerchantMpesaStatus(reference);
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
      if (await _database.getPendingSaleById(saleId) == null) {
        await _createLocalSale(
          saleId: saleId,
          receiptNumber: receiptNumber,
          items: items,
          paymentMethod: 'MPESA',
          total: amount,
          discountAmount: discountAmount,
          paymentReference: reference,
          customerId: customerId,
        );
      }
      await _database.markSaleAsSynced(saleId);
      try {
        await _syncService.pullChanges();
      } catch (_) {}

      _pendingLocalSaleId = null;
      _pendingMpesaFingerprint = null;
      _pendingMpesaRequestId = null;
      state = const PaymentState();
      return saleId;
    } catch (e) {
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

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
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
    state = state.copyWith(isProcessing: true, error: null);

    if (tenders.any((tender) => tender.method == 'MPESA')) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'Use a separate M-Pesa sale for provider-verified shop payouts. Split M-Pesa is not available yet.',
      );
      return null;
    }

    const supportedTenders = {'CASH', 'CREDIT'};
    if (tenders.length < 2 ||
        tenders.any((tender) =>
            !supportedTenders.contains(tender.method) ||
            !tender.amount.isFinite ||
            tender.amount <= 0)) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Split payments need positive amounts for cash or debt only.',
      );
      return null;
    }

    final tenderTotal = tenders.fold<double>(0, (sum, t) => sum + t.amount);
    if ((tenderTotal * 100).round() < (amount * 100).round()) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Tenders (KES ${tenderTotal.toStringAsFixed(2)}) do not cover '
            'the total (KES ${amount.toStringAsFixed(2)})',
      );
      return null;
    }

    final debtPortion = tenders
        .where((t) => t.method == 'CREDIT')
        .fold<double>(0, (sum, t) => sum + t.amount);
    if (debtPortion > 0 &&
        (tenderTotal * 100).round() > (amount * 100).round()) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'A split that includes debt must add up exactly to the amount due. Adjust the cash or debt amounts.',
      );
      return null;
    }
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

      await _syncOrQueueSale(saleId, items, 'SPLIT', tenderTotal, tendersJson,
          tenders, customerId, _SaleExtras(discountAmount, couponCode));

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
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
    double customerBalanceDelta = 0,
    String? paymentReference,
    String? customerId,
  }) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    // Same tax computation the cart uses (AuthService.taxRatePercent, an
    // admin-configured rate, default 0). The previous hardcoded 16% recorded
    // tax the business never charged on offline sales: receipts printed a
    // wrong tax line and subtotal + tax ≠ total.
    final tax =
        (subtotal - discountAmount) * (_authService.taxRatePercent / 100);

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
    if (!_connectivity.isOnline) {
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
      return;
    }

    try {
      final serverReceiptNumber = await _syncSaleToServer(
        saleId,
        items,
        paymentMethod,
        paidAmount,
        paymentReference,
        tenders,
        customerId,
        extras,
      );
      await _database.markSaleAsSynced(saleId);
      // The server numbers every sale itself. Adopt that number locally so the
      // receipt, dashboard, Receipts list and Sales Report all show one ID.
      if (serverReceiptNumber != null && serverReceiptNumber.isNotEmpty) {
        await _database.updateSaleReceiptNumber(saleId, serverReceiptNumber);
      }
      // Refresh canonical stock after a successful online sale. A failed pull
      // is non-fatal: the queued/periodic sync will retry it later.
      try {
        await _syncService.pullChanges();
      } catch (_) {}
    } catch (_) {
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
    }
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

  Future<String?> _syncSaleToServer(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double paidAmount, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
    _SaleExtras extras = const _SaleExtras(),
  ]) async {
    final branchId = _authService.branchId;
    // branchId is a required field on the server (CreateSaleDto.branchId).
    // Without it every POST /sales 400s, the sale is silently re-queued,
    // and server-side stock never decrements. Never send a knowingly
    // invalid request — let the caller's catch queue it for a later retry
    // once a branch is resolved.
    if (branchId == null) {
      throw StateError('Cannot sync sale: no branch selected');
    }

    final created = await _apiClient.createSale({
      'offlineId': saleId,
      'branchId': branchId,
      if (_authService.deviceId != null) 'deviceId': _authService.deviceId,
      if (customerId != null) 'customerId': customerId,
      'items': items
          .map((i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
                'discount': i.discount,
                if (i.saleUnit != null) 'unit': i.saleUnit,
                if (i.unitConversionFactor != null)
                  'quantityPerUnit': i.unitConversionFactor,
              })
          .toList(),
      'paymentMethod': paymentMethod,
      if (extras.discountAmount > 0) 'discountAmount': extras.discountAmount,
      if (extras.couponCode != null) 'couponCode': extras.couponCode,
      // The server's sale schema has no paymentReference or cashierId (the
      // cashier comes from the signed-in token). Sending them made every
      // direct upload fail with 400 and fall back to the slow queue.
      'paidAmount': paidAmount,
      if (tenders != null) 'tenders': tenders.map((t) => t.toJson()).toList(),
    });
    // The API wraps payloads as {success, data}; older responses are bare.
    final payload = created['data'] is Map ? created['data'] as Map : created;
    final number = payload['receiptNumber'];
    return number is String ? number : null;
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
        'items': items.map((i) => i.toJson()).toList(),
        'paymentMethod': paymentMethod,
        'paymentReference': paymentReference,
        if (extras.discountAmount > 0) 'discountAmount': extras.discountAmount,
        if (extras.couponCode != null) 'couponCode': extras.couponCode,
        'paidAmount': paidAmount,
        'cashierId': _authService.userId,
        if (tenders != null) 'tenders': tenders.map((t) => t.toJson()).toList(),
      },
      deviceId: _authService.deviceId!,
      userId: _authService.userId ?? '',
    );
  }

  Future<Map<String, dynamic>?> _pollMerchantMpesaStatus(
      String reference) async {
    // Give the STK prompt a moment to reach the handset, then return control
    // to the cashier. A long 60-second wait kept the only checkout button
    // disabled; the same button safely checks this reference again without
    // starting a second charge.
    await Future<void>.delayed(const Duration(seconds: 2));
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
  return PaymentNotifier(
    apiClient: getIt<ApiClient>(),
    database: getIt<AppDatabase>(),
    syncService: getIt<SyncService>(),
    authService: getIt<AuthService>(),
    connectivity: getIt<ConnectivityService>(),
  );
});
