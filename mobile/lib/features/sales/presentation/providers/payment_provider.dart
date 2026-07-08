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

  const PaymentTender({required this.method, required this.amount, this.reference});

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

  Future<String?> processCashPayment({
    required double amount,
    required List<CartItem> items,
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
      );

      await _syncOrQueueSale(saleId, items, 'CASH', amount);

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
      );

      await _syncOrQueueSale(saleId, items, 'MANUAL', amount);

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
      final paymentSuccessful = await _pollMpesaStatus(checkoutRequestId);

      if (!paymentSuccessful) {
        state = state.copyWith(
          isProcessing: false,
          error: 'M-Pesa payment failed or was cancelled',
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
      );
      await _syncOrQueueSale(saleId, items, 'MPESA', amount, checkoutRequestId);

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
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

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
      );
      await _syncOrQueueSale(saleId, items, 'PESAPAL', amount, orderId);

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
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

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
      );
      await _syncOrQueueSale(
          saleId, items, 'TOURISTTAP', amount, transactionId);

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
      );

      await _syncOrQueueSale(saleId, items, 'CREDIT', amount, customerId);

      state = state.copyWith(isProcessing: false);
      return saleId;
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
      return null;
    }
  }

  /// Records one sale paid via multiple tenders at once (e.g. part cash,
  /// part M-Pesa). [tenders] must sum to at least [amount]; any tender with
  /// method CASH contributes to the till, matching how the backend's
  /// cash-flow ledger only counts the cash portion of a split sale.
  Future<String?> processSplitPayment({
    required double amount,
    required List<CartItem> items,
    required List<PaymentTender> tenders,
  }) async {
    state = state.copyWith(isProcessing: true, error: null);

    final tenderTotal = tenders.fold<double>(0, (sum, t) => sum + t.amount);
    if (tenderTotal < amount) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Tenders (KES ${tenderTotal.toStringAsFixed(2)}) do not cover '
            'the total (KES ${amount.toStringAsFixed(2)})',
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
        total: tenderTotal,
        paymentReference: tendersJson,
      );

      await _syncOrQueueSale(saleId, items, 'SPLIT', tenderTotal, tendersJson, tenders);

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
  }) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    final tax = subtotal * 0.16;

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
  ]) async {
    if (!_connectivity.isOnline) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
        tenders,
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
      );
      await _database.markSaleAsSynced(saleId);
    } catch (_) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
        tenders,
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
  ]) async {
    await _apiClient.createSale({
      'offlineId': saleId,
      'items': items
          .map((i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'unitPrice': i.unitPrice,
                'discount': i.discount,
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
  ]) async {
    await _syncService.queueSyncItem(
      tableName: 'sales',
      recordId: saleId,
      action: SyncAction.create,
      eventType: SyncEventType.saleCreated,
      data: {
        'offlineId': saleId,
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

  Future<bool> _pollMpesaStatus(String checkoutRequestId) async {
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
          return true;
        } else if (normalizedStatus == 'FAILED' ||
            normalizedStatus == 'CANCELLED') {
          return false;
        }
        // Continue polling if still pending
      } catch (e) {
        // Continue polling on error
      }
    }

    return false;
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
