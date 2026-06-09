import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:levisa_adventures_pos/core/di/injection.dart';
import 'package:levisa_adventures_pos/core/database/app_database.dart';

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

  const CartState({
    this.items = const [],
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.customerId,
    this.customerName,
    this.notes,
  });

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);

  double get discount {
    if (discountPercent > 0) {
      return subtotal * (discountPercent / 100);
    }
    return discountAmount;
  }

  double get taxableAmount => subtotal - discount;
  double get tax =>
      taxableAmount *
      0.16; // 16% VAT - TODO: Use product-level tax rates from backend
  double get total => taxableAmount + tax;

  CartState copyWith({
    List<CartItem>? items,
    double? discountPercent,
    double? discountAmount,
    String? customerId,
    String? customerName,
    String? notes,
  }) {
    return CartState(
      items: items ?? this.items,
      discountPercent: discountPercent ?? this.discountPercent,
      discountAmount: discountAmount ?? this.discountAmount,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      notes: notes ?? this.notes,
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
  ParkedSalesNotifier() : super([]);

  void park(CartState cart, {String? label}) {
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
  }

  CartState? resume(String id) {
    final sale = state.firstWhere((s) => s.id == id);
    state = state.where((s) => s.id != id).toList();
    return sale.cart;
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList();
  }
}

final parkedSalesProvider =
    StateNotifierProvider<ParkedSalesNotifier, List<ParkedSale>>((ref) {
      return ParkedSalesNotifier();
    });

// ════════ CART NOTIFIER ════════

class CartNotifier extends StateNotifier<CartState> {
  final AppDatabase _database = getIt<AppDatabase>();

  CartNotifier() : super(const CartState());

  // Stock validation method
  Future<Map<String, dynamic>> _validateStockAvailability(
    String productId,
    int quantity,
  ) async {
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
        currentStock: stockCheck['currentStock'] as int? ?? 0,
      );
    }

    if (existingIndex >= 0) {
      final updatedItems = [...state.items];
      final existing = updatedItems[existingIndex];
      updatedItems[existingIndex] = existing.copyWith(
        quantity: existing.quantity + quantity,
        unitPrice: unitPrice,
        notes: notes,
        saleUnit: saleUnit,
        saleQuantity:
            (existing.saleQuantity ?? existing.quantity.toDouble()) +
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
        currentStock: stockCheck['currentStock'] as int? ?? 0,
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

  void updateItemDiscount(String productId, double discount) {
    final updatedItems = state.items.map((item) {
      if (item.productId == productId) {
        return item.copyWith(discount: discount);
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
  }

  void removeItem(String productId) {
    final updatedItems = state.items
        .where((i) => i.productId != productId)
        .toList();
    state = state.copyWith(items: updatedItems);
  }

  void setDiscountPercent(double percent) {
    state = state.copyWith(discountPercent: percent, discountAmount: 0);
  }

  void setDiscountAmount(double amount) {
    state = state.copyWith(discountAmount: amount, discountPercent: 0);
  }

  void setCustomer(String? customerId, {String? customerName}) {
    state = state.copyWith(customerId: customerId, customerName: customerName);
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
