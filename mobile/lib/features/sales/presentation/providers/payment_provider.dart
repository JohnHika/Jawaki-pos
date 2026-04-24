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
  }) : _apiClient = apiClient,
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
        'accountReference': 'POS-${DateTime.now().millisecondsSinceEpoch}',
        'description': 'POS Sale',
      });
      
      final checkoutRequestId = response['checkoutRequestId'];
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
      await _syncOrQueueSale(saleId, items, 'TOURISTTAP', amount, transactionId);

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
      items.map((item) => PendingSaleItemsCompanion.insert(
        saleId: saleId,
        productId: item.productId,
        productName: item.productName,
        sku: item.sku,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        total: item.total,
      )).toList(),
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
  ]) async {
    if (!_connectivity.isOnline) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
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
      );
      await _database.markSaleAsSynced(saleId);
    } catch (_) {
      await _queueSaleForSync(
        saleId,
        items,
        paymentMethod,
        total,
        paymentReference,
      );
    }
  }
  
  Future<void> _syncSaleToServer(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double total, [
    String? paymentReference,
  ]) async {
    await _apiClient.createSale({
      'offlineId': saleId,
      'items': items.map((i) => {
        'productId': i.productId,
        'quantity': i.quantity,
        'unitPrice': i.unitPrice,
        'discount': i.discount,
      }).toList(),
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'paidAmount': total,
      'cashierId': _authService.userId,
    });
  }
  
  Future<void> _queueSaleForSync(
    String saleId,
    List<CartItem> items,
    String paymentMethod,
    double total,
    [
    String? paymentReference,
  ]
  ) async {
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
        final status = await _apiClient.checkMpesaPaymentStatus(checkoutRequestId);
        
        if (status['status'] == 'COMPLETED') {
          return true;
        } else if (status['status'] == 'FAILED' || status['status'] == 'CANCELLED') {
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
final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  return PaymentNotifier(
    apiClient: getIt<ApiClient>(),
    database: getIt<AppDatabase>(),
    syncService: getIt<SyncService>(),
    authService: getIt<AuthService>(),
    connectivity: getIt<ConnectivityService>(),
  );
});
