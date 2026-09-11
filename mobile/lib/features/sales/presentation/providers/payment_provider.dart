import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart' hide CartItem;
import '../../../../core/network/api_client.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/auth_service.dart';
import 'cart_provider.dart';

const _uuid = Uuid();

/// One payment component of a split sale, e.g. { method: CASH, amount: 500 }.
/// Backend enum values (not the display-only [PaymentMethod] enum in
/// payment_screen.dart) — this must match what CreateSaleDto expects.
class PaymentTender {
  final String method; // 'CASH' | 'MPESA' | 'PESAPAL' | 'TOURISTTAP' | 'CREDIT'
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
  final bool _verifiedDigitalPaymentsEnabled;

  PaymentNotifier({
    required ApiClient apiClient,
    required AppDatabase database,
    required SyncService syncService,
    required AuthService authService,
    required ConnectivityService connectivity,
    bool verifiedDigitalPaymentsEnabled = false,
  })  : _apiClient = apiClient,
        _database = database,
        _syncService = syncService,
        _authService = authService,
        _connectivity = connectivity,
        _verifiedDigitalPaymentsEnabled = verifiedDigitalPaymentsEnabled,
        super(const PaymentState());

  Future<String?> processCashPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

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
        customerId: customerId,
      );

      await _syncOrQueueSale(
          saleId, items, 'CASH', amount, null, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<String?> processManualPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

    try {
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';

      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'MANUAL',
        total: amount,
        customerId: customerId,
      );

      await _syncOrQueueSale(
          saleId, items, 'MANUAL', amount, null, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<String?> processMpesaPayment({
    required double amount,
    required String phoneNumber,
    required List<CartItem> items,
    String? customerId,
  }) async {
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

      // Initiate STK Push
      final response = await _apiClient.initiateMpesaPayment({
        'amount': amount,
        'phoneNumber': formattedPhone,
        'reference': 'POS-${DateTime.now().millisecondsSinceEpoch}',
        'description': 'POS Sale',
      });

      final checkoutRequestId = response['checkout_request_id'];
      state = state.copyWith(currentTransactionId: checkoutRequestId);

      // Poll for payment status
      final pollError = await _pollMpesaStatus(checkoutRequestId);

      if (pollError != null) {
        state = state.copyWith(
          isProcessing: false,
          error: pollError,
        );
        return null;
      }

      // Create sale
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'MPESA',
        total: amount,
        paymentReference: checkoutRequestId,
        customerId: customerId,
      );
      await _syncOrQueueSale(
          saleId, items, 'MPESA', amount, checkoutRequestId, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<String?> processPesaPalPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

    if (!_verifiedDigitalPaymentsEnabled) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'PesaPal is temporarily unavailable while secure payment verification is being enabled.',
      );
      return null;
    }

    if (!_connectivity.isOnline) {
      state = state.copyWith(
        isProcessing: false,
        error: 'PesaPal payments require internet connection',
      );
      return null;
    }

    try {
      final response = await _apiClient.initiatePesaPalPayment({
        'amount': amount,
        'currency': 'KES',
        'description': 'POS Sale',
      });

      // Handle redirect URL for web payment
      // This would typically open a webview
      final orderId = response['orderId'];

      // For now, simulate successful payment
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'PESAPAL',
        total: amount,
        paymentReference: orderId,
        customerId: customerId,
      );
      await _syncOrQueueSale(
          saleId, items, 'PESAPAL', amount, orderId, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<String?> processTouristTapPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

    if (!_verifiedDigitalPaymentsEnabled) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'TouristTap is temporarily unavailable while secure payment verification is being enabled.',
      );
      return null;
    }

    if (!_connectivity.isOnline) {
      state = state.copyWith(
        isProcessing: false,
        error: 'TouristTap payments require internet connection',
      );
      return null;
    }

    try {
      final response = await _apiClient.initiateTouristTapPayment({
        'amount': amount,
        'currency': 'KES',
      });

      final transactionId = response['transactionId'];

      // NFC payment would be initiated here
      // For now, simulate successful payment
      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'TOURISTTAP',
        total: amount,
        paymentReference: transactionId,
        customerId: customerId,
      );
      await _syncOrQueueSale(
          saleId, items, 'TOURISTTAP', amount, transactionId, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<String?> processCreditPayment({
    required double amount,
    required List<CartItem> items,
    String? customerId,
    String? customerName,
    String? notes,
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
        paymentReference: customerId,
        customerId: customerId,
      );

      // The whole amount is owed — add it to the customer's running debt
      // balance so the Customers screen and profile reflect what they owe.
      await _database.updateCustomerBalance(customerId, amount);

      await _syncOrQueueSale(
          saleId, items, 'CREDIT', amount, customerId, null, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  /// Records one sale paid via multiple tenders at once (e.g. part cash,
  /// part M-Pesa, part debt). [tenders] must sum to at least [amount]; any
  /// tender with method CASH contributes to the till, and any tender with
  /// method CREDIT is added to the customer's debt balance (which is why a
  /// customer is required when a split includes a debt portion).
  Future<String?> processSplitPayment({
    required double amount,
    required List<CartItem> items,
    required List<PaymentTender> tenders,
    String? customerId,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

    // MPESA sits alongside CASH and CREDIT as an always-available split
    // tender (a standalone MPESA sale already works without any digital
    // -payments flag — only PesaPal/TouristTap are gated behind
    // _verifiedDigitalPaymentsEnabled, and that gate carries through here
    // unchanged for anything else).
    const supportedTenders = {'CASH', 'CREDIT', 'MPESA'};
    if (!_verifiedDigitalPaymentsEnabled &&
        tenders.any((tender) => !supportedTenders.contains(tender.method))) {
      state = state.copyWith(
        isProcessing: false,
        error:
            'Split payments can only use cash, M-Pesa and debt until digital payment verification is enabled.',
      );
      return null;
    }

    final tenderTotal = tenders.fold<double>(0, (sum, t) => sum + t.amount);
    if (tenderTotal < amount) {
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
    if (debtPortion > 0 && customerId == null) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Select a customer before adding a debt portion',
      );
      return null;
    }

    final mpesaTenders = tenders.where((t) => t.method == 'MPESA').toList();
    if (mpesaTenders.isNotEmpty && !_connectivity.isOnline) {
      state = state.copyWith(
        isProcessing: false,
        error: 'The M-Pesa portion of a split payment requires internet connection',
      );
      return null;
    }

    try {
      // Charge every M-Pesa tender FIRST, before the sale is created — a
      // failed/declined STK push must never leave a half-created sale
      // behind. Each confirmed tender's reference becomes the checkout
      // request id, matching the standalone M-Pesa payment path.
      var resolvedTenders = tenders;
      if (mpesaTenders.isNotEmpty) {
        final confirmed = <PaymentTender>[];
        for (final tender in tenders) {
          if (tender.method != 'MPESA') {
            confirmed.add(tender);
            continue;
          }
          final phone = tender.reference;
          if (phone == null || phone.isEmpty) {
            state = state.copyWith(
              isProcessing: false,
              error: 'Enter the M-Pesa phone number for the split payment',
            );
            return null;
          }
          String formattedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
          if (formattedPhone.startsWith('0')) {
            formattedPhone = '254${formattedPhone.substring(1)}';
          } else if (!formattedPhone.startsWith('254')) {
            formattedPhone = '254$formattedPhone';
          }
          final response = await _apiClient.initiateMpesaPayment({
            'amount': tender.amount,
            'phoneNumber': formattedPhone,
            'reference': 'POS-SPLIT-${DateTime.now().millisecondsSinceEpoch}',
            'description': 'POS Split Sale',
          });
          final checkoutRequestId = response['checkout_request_id'];
          final pollError = await _pollMpesaStatus(checkoutRequestId);
          if (pollError != null) {
            state = state.copyWith(isProcessing: false, error: pollError);
            return null;
          }
          confirmed.add(PaymentTender(
            method: 'MPESA',
            amount: tender.amount,
            reference: checkoutRequestId,
          ));
        }
        resolvedTenders = confirmed;
      }

      final saleId = _uuid.v4();
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';

      // Tenders are stored as JSON in paymentReference — SPLIT is the only
      // payment method whose "reference" is structured data rather than a
      // single external transaction id, reusing the field rather than
      // adding a dedicated column/migration for what's still a single
      // nullable string slot everywhere else.
      final tendersJson =
          jsonEncode(resolvedTenders.map((t) => t.toJson()).toList());

      await _createLocalSale(
        saleId: saleId,
        receiptNumber: receiptNumber,
        items: items,
        paymentMethod: 'SPLIT',
        total: tenderTotal,
        paymentReference: tendersJson,
        customerId: customerId,
      );

      // The debt portion of the split becomes customer debt.
      if (debtPortion > 0 && customerId != null) {
        await _database.updateCustomerBalance(customerId, debtPortion);
      }

      await _syncOrQueueSale(saleId, items, 'SPLIT', tenderTotal, tendersJson,
          resolvedTenders, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  Future<void> _createLocalSale({
    required String saleId,
    required String receiptNumber,
    required List<CartItem> items,
    required String paymentMethod,
    required double total,
    String? paymentReference,
    String? customerId,
  }) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    // Same tax computation the cart uses (AuthService.taxRatePercent, an
    // admin-configured rate, default 0). The previous hardcoded 16% recorded
    // tax the business never charged on offline sales: receipts printed a
    // wrong tax line and subtotal + tax ≠ total.
    final tax = subtotal * (_authService.taxRatePercent / 100);

    // Create pending sale in local database
    await _database.createPendingSale(
      PendingSalesCompanion.insert(
        id: saleId,
        receiptNumber: receiptNumber,
        subtotal: subtotal,
        tax: Value(tax),
        total: total,
        paymentMethod: paymentMethod,
        paymentReference: Value(paymentReference),
        customerId: Value(customerId),
        cashierId: _authService.userId!,
        branchId: _authService.branchId!,
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
    );

    // Decrement local stock
    for (final item in items) {
      await _database.decrementStock(
        item.productId,
        _authService.branchId!,
        item.quantity,
      );
    }
  }

  Future<void> _syncOrQueueSale(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double total, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
  ]) async {
    if (!_connectivity.isOnline) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
        tenders,
        customerId,
      );
      return;
    }

    try {
      await _syncSaleToServer(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
        tenders,
        customerId,
      );
      await _database.markSaleAsSynced(saleId);
      // Refresh canonical stock after a successful online sale. A failed pull
      // is non-fatal: the queued/periodic sync will retry it later.
      try {
        await _syncService.pullChanges();
      } catch (_) {}
    } catch (_) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
        tenders,
        customerId,
      );
    }
  }

  Future<void> _syncSaleToServer(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double total, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
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

    await _apiClient.createSale({
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
      'paymentReference': paymentReference,
      'paidAmount': total,
      'cashierId': _authService.userId,
      if (tenders != null) 'tenders': tenders.map((t) => t.toJson()).toList(),
    });
  }

  Future<void> _queueSaleForSync(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double total, [
    String? paymentReference,
    List<PaymentTender>? tenders,
    String? customerId,
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
        'paidAmount': total,
        'cashierId': _authService.userId,
        if (tenders != null) 'tenders': tenders.map((t) => t.toJson()).toList(),
      },
      deviceId: _authService.deviceId!,
      userId: _authService.userId ?? '',
    );
  }

  /// Returns null when the payment completed, otherwise an error message
  /// describing why the sale was not created.
  Future<String?> _pollMpesaStatus(String checkoutRequestId) async {
    const maxAttempts = 30;
    const pollInterval = Duration(seconds: 2);

    for (var i = 0; i < maxAttempts; i++) {
      await Future.delayed(pollInterval);

      try {
        final status =
            await _apiClient.checkMpesaPaymentStatus(checkoutRequestId);
        final normalizedStatus =
            (status['status'] as String? ?? '').toUpperCase();

        if (normalizedStatus == 'COMPLETED') {
          return null;
        } else if (normalizedStatus == 'FAILED' ||
            normalizedStatus == 'CANCELLED') {
          return 'M-Pesa payment failed or was cancelled';
        }
        // Continue polling if still pending
      } catch (e) {
        // Continue polling on error
      }
    }

    // Poll exhaustion is NOT a confirmed failure: the STK push may still
    // complete on the customer's phone. Report it as pending so the cashier
    // verifies before retrying — retrying now could double-charge.
    return 'M-Pesa payment is still pending. Verify the payment with the '
        'customer before retrying to avoid double-charging.';
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
