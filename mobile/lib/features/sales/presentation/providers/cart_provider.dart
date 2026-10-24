import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/coupon_rules.dart';
import 'package:axon_pos/core/services/storage_service.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

const _uuid = Uuid();

class CartItem {
  final String id;
  final String productId;
  final String productName;
  final String sku;
  final int quantity;
  final double unitPrice;
  final double discount;
  final String? notes;
  final String? saleUnit;
  final double? saleQuantity;
  final double? unitConversionFactor;

  CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    this.notes,
    this.saleUnit,
    this.saleQuantity,
    this.unitConversionFactor,
  });

  double get total => (unitPrice * quantity) - discount;

  CartItem copyWith({
    String? id,
    String? productId,
    String? productName,
    String? sku,
    int? quantity,
    double? unitPrice,
    double? discount,
    String? notes,
    String? saleUnit,
    double? saleQuantity,
    double? unitConversionFactor,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      notes: notes ?? this.notes,
      saleUnit: saleUnit ?? this.saleUnit,
      saleQuantity: saleQuantity ?? this.saleQuantity,
      unitConversionFactor: unitConversionFactor ?? this.unitConversionFactor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productName': productName,
      'sku': sku,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'discount': discount,
      'total': total,
      'notes': notes,
      'saleUnit': saleUnit,
      'saleQuantity': saleQuantity,
      'unitConversionFactor': unitConversionFactor,
    };
  }
}

class CartMutationResult {
  final bool success;
  final String message;
  final int currentStock;

  const CartMutationResult({
    required this.success,
    required this.message,
    this.currentStock = 0,
  });

  const CartMutationResult.success([String message = 'Updated cart'])
      : this(success: true, message: message);
}

class CartState {
  final List<CartItem> items;
  final double discountPercent;
  final double discountAmount;
  final String? customerId;
  final String? customerName;
  final String? notes;

  /// A shop coupon the cashier entered. Its value is worked out from the
  /// lines every time (see [couponVerdict]), so it follows the cart: remove an
  /// item and a minimum-spend coupon stops applying instead of overpaying.
  final Coupon? coupon;

  const CartState({
    this.items = const [],
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.customerId,
    this.customerName,
    this.notes,
    this.coupon,
  });

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);

  /// The cashier's own discount, which the shop's discount limit applies to.
  double get manualDiscount {
    if (discountPercent > 0) {
      return subtotal * (discountPercent / 100);
    }
    return discountAmount;
  }

  List<CouponLine> get couponLines => [
        for (final item in items)
          CouponLine(productId: item.productId, amount: item.total),
      ];

  CouponVerdict? get couponVerdict => coupon == null
      ? null
      : evaluateCoupon(coupon!, couponLines, customerId: customerId);

  /// What the coupon takes off right now; zero if it no longer qualifies.
  double get couponDiscount {
    final verdict = couponVerdict;
    if (verdict == null || !verdict.ok) return 0;
    final room = subtotal - manualDiscount;
    return verdict.discount > room ? (room > 0 ? room : 0) : verdict.discount;
  }

  /// This coupon's share of each line, in cart order, for the price guard.
  List<double> get couponShares => couponDiscount > 0
      ? spreadCouponDiscount(couponLines, coupon!.productIds, couponDiscount)
      : List<double>.filled(items.length, 0);

  double get discount => manualDiscount + couponDiscount;

  double get taxableAmount => subtotal - discount;

  /// Tax rate is a business-level setting an admin configures in Settings
  /// (defaults to 0 — no tax — until they set one), not a fixed assumption.
  double get tax => taxableAmount * (getIt<AuthService>().taxRatePercent / 100);
  double get total => taxableAmount + tax;

  CartState copyWith({
    List<CartItem>? items,
    double? discountPercent,
    double? discountAmount,
    String? customerId,
    String? customerName,
    bool clearCustomer = false,
    String? notes,
    Coupon? coupon,
    bool clearCoupon = false,
  }) {
    return CartState(
      items: items ?? this.items,
      discountPercent: discountPercent ?? this.discountPercent,
      discountAmount: discountAmount ?? this.discountAmount,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      notes: notes ?? this.notes,
      coupon: clearCoupon ? null : (coupon ?? this.coupon),
    );
  }
}

// ════════ PARKED / STASHED SALES ════════

class ParkedSale {
  final String id;
  final String label;
  final CartState cart;
  final DateTime parkedAt;

  ParkedSale({
    required this.id,
    required this.label,
    required this.cart,
    required this.parkedAt,
  });
}

class ParkedSalesNotifier extends StateNotifier<List<ParkedSale>> {
  ParkedSalesNotifier({
    required StorageService storage,
    required String? tenantId,
    required String? branchId,
  })  : _storage = storage,
        _tenantId = tenantId,
        _branchId = branchId,
        super(_restore(storage, tenantId, branchId));

  final StorageService _storage;
  final String? _tenantId;
  final String? _branchId;
  Future<void> _lastWrite = Future<void>.value();

  static double? _amount(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite ? number : null;
  }

  static List<ParkedSale> _restore(
      StorageService storage, String? tenantId, String? branchId) {
    if (tenantId == null ||
        tenantId.isEmpty ||
        branchId == null ||
        branchId.isEmpty) {
      return const [];
    }
    final raw =
        storage.getHeldSalesSnapshot(tenantId: tenantId, branchId: branchId);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['tenantId'] != tenantId ||
          decoded['branchId'] != branchId ||
          decoded['sales'] is! List) {
        return const [];
      }
      final restored = <ParkedSale>[];
      for (final row in decoded['sales'] as List) {
        if (row is! Map || row['cart'] is! Map) continue;
        try {
          final cartJson = Map<String, dynamic>.from(row['cart'] as Map);
          if (cartJson['items'] is! List) continue;
          final items = <CartItem>[];
          for (final item in cartJson['items'] as List) {
            if (item is! Map) continue;
            final id = item['id']?.toString() ?? '';
            final productId = item['productId']?.toString() ?? '';
            final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
            final price = _amount(item['unitPrice']);
            final discount = _amount(item['discount']) ?? 0;
            if (id.isEmpty ||
                productId.isEmpty ||
                quantity <= 0 ||
                price == null ||
                price < 0 ||
                discount < 0) {
              continue;
            }
            items.add(CartItem(
              id: id,
              productId: productId,
              productName: item['productName']?.toString() ?? '',
              sku: item['sku']?.toString() ?? '',
              quantity: quantity,
              unitPrice: price,
              discount: discount,
              notes: item['notes']?.toString(),
              saleUnit: item['saleUnit']?.toString(),
              saleQuantity: _amount(item['saleQuantity']),
              unitConversionFactor: _amount(item['unitConversionFactor']),
            ));
          }
          if (items.isEmpty) continue;
          final parkedAt = DateTime.tryParse(row['parkedAt']?.toString() ?? '');
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty || parkedAt == null) continue;
          Coupon? coupon;
          if (cartJson['coupon'] is Map) {
            try {
              coupon = Coupon.fromJson(
                  Map<String, dynamic>.from(cartJson['coupon'] as Map));
            } catch (_) {
              // A malformed coupon must not discard the rest of the held cart.
            }
          }
          restored.add(ParkedSale(
            id: id,
            label: row['label']?.toString() ?? 'Held sale',
            parkedAt: parkedAt,
            cart: CartState(
              items: items,
              discountPercent: _amount(cartJson['discountPercent']) ?? 0,
              discountAmount: _amount(cartJson['discountAmount']) ?? 0,
              customerId: cartJson['customerId']?.toString(),
              customerName: cartJson['customerName']?.toString(),
              notes: cartJson['notes']?.toString(),
              coupon: coupon,
            ),
          ));
        } catch (_) {
          // Skip an invalid entry while preserving other held sales.
        }
      }
      return restored;
    } catch (_) {
      return const [];
    }
  }

  void _persist() {
    final tenantId = _tenantId;
    final branchId = _branchId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        branchId == null ||
        branchId.isEmpty) {
      return;
    }
    final snapshot = jsonEncode({
      'version': 1,
      'tenantId': tenantId,
      'branchId': branchId,
      'sales': [
        for (final sale in state)
          {
            'id': sale.id,
            'label': sale.label,
            'parkedAt': sale.parkedAt.toUtc().toIso8601String(),
            'cart': {
              'items': [for (final item in sale.cart.items) item.toJson()],
              'discountPercent': sale.cart.discountPercent,
              'discountAmount': sale.cart.discountAmount,
              'customerId': sale.cart.customerId,
              'customerName': sale.cart.customerName,
              'notes': sale.cart.notes,
              'coupon': sale.cart.coupon?.toJson(),
            },
          },
      ],
    });
    // Queue writes so a quick hold/resume sequence cannot restore an older
    // snapshot after a newer one. Keep the queue usable after an I/O error.
    _lastWrite = _lastWrite
        .then((_) => _storage.saveHeldSalesSnapshot(
              tenantId: tenantId,
              branchId: branchId,
              snapshot: snapshot,
            ))
        .catchError((Object error) {
      debugPrint('[HeldSales] Could not save held sales: $error');
    });
  }

  void park(CartState cart, {String? label}) {
    if (cart.items.isEmpty) return;
    final name = label ?? cart.customerName ?? 'Sale #${state.length + 1}';
    state = [
      ...state,
      ParkedSale(
        id: _uuid.v4(),
        label: name,
        cart: cart,
        parkedAt: DateTime.now(),
      ),
    ];
    _persist();
  }

  CartState? resume(String id) {
    final index = state.indexWhere((s) => s.id == id);
    if (index < 0) return null;
    final sale = state[index];
    state = state.where((s) => s.id != id).toList();
    _persist();
    return sale.cart;
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList();
    _persist();
  }
}

final parkedSalesProvider =
    StateNotifierProvider<ParkedSalesNotifier, List<ParkedSale>>((ref) {
  final scope = ref.watch(authControllerProvider.select((auth) => auth
          .isAuthenticated
      ? (auth.user?['tenantId']?.toString(), auth.user?['branchId']?.toString())
      : (null, null)));
  return ParkedSalesNotifier(
    storage: getIt<StorageService>(),
    tenantId: scope.$1,
    branchId: scope.$2,
  );
});

// ════════ CART NOTIFIER ════════

class CartNotifier extends StateNotifier<CartState> {
  AppDatabase get _database => getIt<AppDatabase>();

  /// Replaces the database-backed stock check; used by tests.
  final Future<Map<String, dynamic>> Function(String productId, int quantity)?
      _stockValidator;

  CartNotifier({
    Future<Map<String, dynamic>> Function(String productId, int quantity)?
        stockValidator,
  })  : _stockValidator = stockValidator,
        super(const CartState());

  // Stock validation method
  Future<Map<String, dynamic>> _validateStockAvailability(
    String productId,
    int quantity,
  ) async {
    final override = _stockValidator;
    if (override != null) return override(productId, quantity);
    try {
      final product = await _database.getProduct(productId);
      if (product != null && !product.trackInventory) {
        return {
          'available': true,
          'message': 'Inventory tracking disabled',
          'currentStock': quantity,
          'required': quantity,
        };
      }

      final stock = await _database.getStockForProduct(productId);

      if (stock == null) {
        return {
          'available': false,
          'message': 'Product not found in inventory',
          'currentStock': 0,
          'required': quantity,
        };
      }

      if (stock.quantity <= 0) {
        return {
          'available': false,
          'message': 'Product is out of stock',
          'currentStock': stock.quantity,
          'required': quantity,
        };
      }

      if (stock.quantity < quantity) {
        return {
          'available': false,
          'message': 'Insufficient stock available',
          'currentStock': stock.quantity,
          'required': quantity,
          'availableQuantity': stock.quantity,
        };
      }

      return {
        'available': true,
        'message': 'Stock available',
        'currentStock': stock.quantity,
        'required': quantity,
      };
    } catch (e) {
      return {
        'available': false,
        'message': 'Error checking stock: $e',
        'currentStock': 0,
        'required': quantity,
      };
    }
  }

  Future<CartMutationResult> addItem({
    required String productId,
    required String productName,
    required String sku,
    required double unitPrice,
    int quantity = 1,
    double discount = 0,
    String? notes,
    String? saleUnit,
    double? saleQuantity,
    double? unitConversionFactor,
  }) async {
    final existingIndex = state.items.indexWhere(
      (i) => i.productId == productId,
    );
    final requestedQuantity = existingIndex >= 0
        ? state.items[existingIndex].quantity + quantity
        : quantity;
    final stockCheck = await _validateStockAvailability(
      productId,
      requestedQuantity,
    );

    if (!stockCheck['available']) {
      return CartMutationResult(
        success: false,
        message: stockCheck['message'] as String? ?? 'Insufficient stock',
        currentStock: (stockCheck['currentStock'] as num?)?.floor() ?? 0,
      );
    }

    // The stock check above is asynchronous, so look the line up again: a fast
    // second tap on a product that was not yet in the cart must add to the line
    // the first tap created, not start a duplicate one.
    final freshIndex = state.items.indexWhere((i) => i.productId == productId);
    if (freshIndex >= 0) {
      final updatedItems = [...state.items];
      final existing = updatedItems[freshIndex];
      updatedItems[freshIndex] = existing.copyWith(
        quantity: existing.quantity + quantity,
        unitPrice: unitPrice,
        notes: notes,
        saleUnit: saleUnit,
        saleQuantity: (existing.saleQuantity ?? existing.quantity.toDouble()) +
            (saleQuantity ?? quantity.toDouble()),
        unitConversionFactor: unitConversionFactor,
      );
      state = state.copyWith(items: updatedItems);
    } else {
      final newItem = CartItem(
        id: _uuid.v4(),
        productId: productId,
        productName: productName,
        sku: sku,
        quantity: quantity,
        unitPrice: unitPrice,
        discount: discount,
        notes: notes,
        saleUnit: saleUnit,
        saleQuantity: saleQuantity,
        unitConversionFactor: unitConversionFactor,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
    return const CartMutationResult.success();
  }

  Future<CartMutationResult> updateQuantity(
    String productId,
    int quantity,
  ) async {
    if (quantity <= 0) {
      removeItem(productId);
      return const CartMutationResult.success('Removed item');
    }

    final stockCheck = await _validateStockAvailability(productId, quantity);

    if (!stockCheck['available']) {
      return CartMutationResult(
        success: false,
        message: stockCheck['message'] as String? ?? 'Insufficient stock',
        currentStock: (stockCheck['currentStock'] as num?)?.floor() ?? 0,
      );
    }

    final updatedItems = state.items.map((item) {
      if (item.productId == productId) {
        final conversion = item.unitConversionFactor;
        return item.copyWith(
          quantity: quantity,
          saleQuantity: conversion != null && conversion > 0
              ? quantity / conversion
              : item.saleQuantity,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
    return const CartMutationResult.success();
  }

  /// Moves a line already in the cart up or down by [delta] BASE units,
  /// keeping that line's price and unit. The result is worked out from the cart
  /// as it is AFTER the stock check, so rapid taps accumulate instead of
  /// overwriting each other. Going to zero or below removes the line.
  Future<CartMutationResult> changeQuantityBy(
      String productId, int delta) async {
    final index = state.items.indexWhere((i) => i.productId == productId);
    if (index < 0) {
      return const CartMutationResult(
        success: false,
        message: 'Item is not in the cart',
      );
    }
    if (delta == 0) return const CartMutationResult.success();

    if (delta > 0) {
      final wanted = state.items[index].quantity + delta;
      final stockCheck = await _validateStockAvailability(productId, wanted);
      if (!stockCheck['available']) {
        return CartMutationResult(
          success: false,
          message: stockCheck['message'] as String? ?? 'Insufficient stock',
          currentStock: (stockCheck['currentStock'] as num?)?.floor() ?? 0,
        );
      }
    }

    final latest = state.items.indexWhere((i) => i.productId == productId);
    if (latest < 0) return const CartMutationResult.success();
    final newQuantity = state.items[latest].quantity + delta;
    if (newQuantity <= 0) {
      removeItem(productId);
      return const CartMutationResult.success('Removed item');
    }

    final updatedItems = [...state.items];
    final item = updatedItems[latest];
    final conversion = item.unitConversionFactor;
    updatedItems[latest] = item.copyWith(
      quantity: newQuantity,
      saleQuantity: conversion != null && conversion > 0
          ? newQuantity / conversion
          : item.saleQuantity,
    );
    state = state.copyWith(items: updatedItems);
    return const CartMutationResult.success();
  }

  void updateItemDiscount(String productId, double discount, {String? reason}) {
    final updatedItems = state.items.map((item) {
      if (item.productId == productId) {
        return item.copyWith(
          discount: discount,
          notes: reason?.isNotEmpty == true ? reason : item.notes,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
  }

  void removeItem(String productId) {
    final updatedItems =
        state.items.where((i) => i.productId != productId).toList();
    state = state.copyWith(items: updatedItems);
  }

  void setDiscountPercent(double percent) {
    state = state.copyWith(discountPercent: percent, discountAmount: 0);
  }

  void setDiscountAmount(double amount) {
    state = state.copyWith(discountAmount: amount, discountPercent: 0);
  }

  void applyCoupon(Coupon coupon) {
    state = state.copyWith(coupon: coupon);
  }

  void removeCoupon() {
    state = state.copyWith(clearCoupon: true);
  }

  void setCustomer(String? customerId, {String? customerName}) {
    state = state.copyWith(
      customerId: customerId,
      customerName: customerName,
      clearCustomer: customerId == null,
    );
  }

  void setNotes(String? notes) {
    state = state.copyWith(notes: notes);
  }

  void restoreFrom(CartState saved) {
    state = saved;
  }

  void clear() {
    state = const CartState();
  }

  // Validate stock for entire cart
  Future<List<Map<String, dynamic>>> validateCartStock() async {
    final results = <Map<String, dynamic>>[];

    for (final item in state.items) {
      final stockCheck = await _validateStockAvailability(
        item.productId,
        item.quantity,
      );
      results.add({
        'productId': item.productId,
        'productName': item.productName,
        'sku': item.sku,
        'requestedQuantity': item.quantity,
        'available': stockCheck['available'],
        'message': stockCheck['message'],
        'currentStock': stockCheck['currentStock'],
      });
    }

    return results;
  }

  List<Map<String, dynamic>> getItemsForApi() {
    return state.items
        .map(
          (item) => {
            'productId': item.productId,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'discount': item.discount,
          },
        )
        .toList();
  }
}

// Provider
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
