import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/coupon_rules.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/utils/api_message.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

const _uuid = Uuid();

double _quantityAtSupportedPrecision(num value) =>
    double.parse(value.toDouble().toStringAsFixed(3));

class CartItem {
  final String id;
  final String productId;
  final String productName;
  final String sku;
  final double quantity;
  final double unitPrice;
  final double discount;
  final String? notes;
  final String? saleUnit;
  final double? saleQuantity;
  final double? unitConversionFactor;
  final bool allowFractions;

  CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    required num quantity,
    required this.unitPrice,
    this.discount = 0,
    this.notes,
    this.saleUnit,
    this.saleQuantity,
    this.unitConversionFactor,
    this.allowFractions = false,
  }) : quantity = quantity.toDouble();

  double get total => (unitPrice * quantity) - discount;

  CartItem copyWith({
    String? id,
    String? productId,
    String? productName,
    String? sku,
    num? quantity,
    double? unitPrice,
    double? discount,
    String? notes,
    String? saleUnit,
    double? saleQuantity,
    double? unitConversionFactor,
    bool? allowFractions,
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
      allowFractions: allowFractions ?? this.allowFractions,
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
      'allowFractions': allowFractions,
    };
  }
}

class CartMutationResult {
  final bool success;
  final String message;
  final double currentStock;

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

  // Preserve the existing integer count for whole units and count a partial
  // measured unit as one item in integer-only badge/summary controls.
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity.ceil());

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);

  /// The cashier's own discount, which the shop's discount limit applies to.
  double get manualDiscount {
    final gross = subtotal;
    if (!gross.isFinite || gross <= 0) return 0;
    final requested =
        discountPercent > 0 ? gross * (discountPercent / 100) : discountAmount;
    if (!requested.isFinite || requested <= 0) return 0;
    return requested.clamp(0, gross).toDouble();
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
            final quantity =
                _quantityAtSupportedPrecision(_amount(item['quantity']) ?? 0);
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
            final gross = price * quantity;
            if (!gross.isFinite) continue;
            final grossCents = (gross * 100).round();
            final safeDiscountCents = (discount * 100).round();
            items.add(CartItem(
              id: id,
              productId: productId,
              productName: item['productName']?.toString() ?? '',
              sku: item['sku']?.toString() ?? '',
              quantity: quantity,
              unitPrice: price,
              // Older held carts can contain an out-of-range line discount.
              // Keep the sale resumable while ensuring its line total cannot
              // become negative.
              discount: safeDiscountCents.clamp(0, grossCents) / 100,
              notes: item['notes']?.toString(),
              saleUnit: item['saleUnit']?.toString(),
              saleQuantity: _amount(item['saleQuantity']),
              unitConversionFactor: _amount(item['unitConversionFactor']),
              allowFractions: item['allowFractions'] == true,
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

  int _sessionGeneration = 0;

  /// Replaces the database-backed stock check; used by tests.
  final Future<Map<String, dynamic>> Function(
      String productId, double quantity)? _stockValidator;

  CartNotifier({
    Future<Map<String, dynamic>> Function(String productId, double quantity)?
        stockValidator,
  })  : _stockValidator = stockValidator,
        super(const CartState());

  /// Drops sale data when the signed-in cashier, tenant, or branch changes.
  /// The generation also prevents stock checks started by the previous session
  /// from writing into the new session's cart when they finish late.
  void resetForSession() {
    _sessionGeneration++;
    state = const CartState();
  }

  // Stock validation method
  Future<Map<String, dynamic>> _validateStockAvailability(
    String productId,
    double quantity,
  ) async {
    final override = _stockValidator;
    if (override != null) return override(productId, quantity);
    try {
      final product = await _database.getProduct(productId);
      if (quantity % 1 != 0 && product?.allowFractions != true) {
        return {
          'available': false,
          'message': 'This product is sold in whole units.',
          'currentStock':
              (await _database.getStockForProduct(productId))?.quantity ?? 0,
          'required': quantity,
        };
      }
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
        'message': 'Could not verify stock. ${apiErrorMessage(e)}',
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
    num quantity = 1,
    double discount = 0,
    String? notes,
    String? saleUnit,
    double? saleQuantity,
    double? unitConversionFactor,
    bool allowFractions = false,
  }) async {
    final sessionGeneration = _sessionGeneration;
    final quantityValue = _quantityAtSupportedPrecision(quantity);
    if (!quantityValue.isFinite ||
        quantityValue <= 0 ||
        (!allowFractions && quantityValue % 1 != 0) ||
        !unitPrice.isFinite ||
        unitPrice < 0) {
      return const CartMutationResult(
        success: false,
        message: 'Enter a valid price and quantity before adding this item.',
      );
    }
    final newLineTotal = unitPrice * quantityValue;
    if (!newLineTotal.isFinite) {
      return const CartMutationResult(
        success: false,
        message: 'The item price is too large to add to this sale.',
      );
    }
    if (!discount.isFinite || discount < 0 || discount > newLineTotal) {
      return const CartMutationResult(
        success: false,
        message: 'The item discount must be between KES 0 and its line total.',
      );
    }
    final newLineCents = (newLineTotal * 100).round();
    final discountCents = (discount * 100).round();
    if (discountCents > newLineCents) {
      return const CartMutationResult(
        success: false,
        message: 'The item discount must be between KES 0 and its line total.',
      );
    }
    final conversion = unitConversionFactor ?? 1;
    final existingIndex = state.items.indexWhere((item) =>
        item.productId == productId &&
        _sameSaleTier(item, saleUnit, conversion));
    final otherTierExists = state.items.any((item) =>
        item.productId == productId &&
        !_sameSaleTier(item, saleUnit, conversion));
    // Keep one line per product. A caller that wants to change the unit or
    // tier must explicitly update that line; silently merging a piece into a
    // box line changes the price basis for stock that was already in the cart.
    if (otherTierExists && existingIndex < 0) {
      return const CartMutationResult(
        success: false,
        message:
            'This product is already in the cart at another sale unit. Open it to update the quantity or unit.',
      );
    }
    final requestedQuantity = _quantityAtSupportedPrecision(existingIndex >= 0
        ? state.items[existingIndex].quantity + quantityValue
        : quantityValue);
    final stockCheck = await _validateStockAvailability(
      productId,
      requestedQuantity,
    );

    if (sessionGeneration != _sessionGeneration) {
      return const CartMutationResult(
        success: false,
        message: 'Your session changed. Start this sale again.',
      );
    }

    if (!stockCheck['available']) {
      return CartMutationResult(
        success: false,
        message: stockCheck['message'] as String? ?? 'Insufficient stock',
        currentStock: (stockCheck['currentStock'] as num?)?.toDouble() ?? 0,
      );
    }

    // The stock check above is asynchronous, so look the line up again: a fast
    // second tap on a product that was not yet in the cart must add to the line
    // the first tap created, not start a duplicate one.
    final freshIndex = state.items.indexWhere((item) =>
        item.productId == productId &&
        _sameSaleTier(item, saleUnit, conversion));
    final freshOtherTierExists = state.items.any((item) =>
        item.productId == productId &&
        !_sameSaleTier(item, saleUnit, conversion));
    if (freshIndex < 0 && freshOtherTierExists) {
      return const CartMutationResult(
        success: false,
        message:
            'This product is already in the cart at another sale unit. Open it to update the quantity or unit.',
      );
    }
    if (freshIndex >= 0) {
      final updatedItems = [...state.items];
      final existing = updatedItems[freshIndex];
      final nextQuantity =
          _quantityAtSupportedPrecision(existing.quantity + quantityValue);
      updatedItems[freshIndex] = existing.copyWith(
        quantity: nextQuantity,
        discount: _scaledDiscount(existing,
            quantity: nextQuantity, unitPrice: existing.unitPrice),
        // Preserve a manually adjusted/tier price on the existing line.
        // This action adds quantity; it is not a repricing operation.
        saleQuantity: _quantityAtSupportedPrecision(
          (existing.saleQuantity ??
                  existing.quantity / (existing.unitConversionFactor ?? 1)) +
              (saleQuantity ?? quantityValue / conversion),
        ),
      );
      state = state.copyWith(items: updatedItems);
    } else {
      final newItem = CartItem(
        id: _uuid.v4(),
        productId: productId,
        productName: productName,
        sku: sku,
        quantity: quantityValue,
        unitPrice: unitPrice,
        discount: discount,
        notes: notes,
        saleUnit: saleUnit,
        saleQuantity: saleQuantity,
        unitConversionFactor: unitConversionFactor,
        allowFractions: allowFractions,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
    return const CartMutationResult.success();
  }

  Future<CartMutationResult> updateQuantity(
    String productId,
    num quantity, {
    double? unitPrice,
    String? notes,
    String? saleUnit,
    double? saleQuantity,
    double? unitConversionFactor,
  }) async {
    final sessionGeneration = _sessionGeneration;
    final quantityValue = _quantityAtSupportedPrecision(quantity);
    if (!quantityValue.isFinite || quantityValue < 0) {
      return const CartMutationResult(
        success: false,
        message: 'Enter a valid quantity.',
      );
    }
    if (quantityValue == 0) {
      removeItem(productId);
      return const CartMutationResult.success('Removed item');
    }
    if (unitPrice != null && (!unitPrice.isFinite || unitPrice < 0)) {
      return const CartMutationResult(
        success: false,
        message: 'Enter a valid item price.',
      );
    }
    final currentItemIndex =
        state.items.indexWhere((item) => item.productId == productId);
    final currentItem =
        currentItemIndex < 0 ? null : state.items[currentItemIndex];
    if (quantityValue % 1 != 0 && currentItem?.allowFractions != true) {
      return const CartMutationResult(
        success: false,
        message: 'This product is sold in whole units.',
      );
    }
    final resultingUnitPrice = unitPrice ?? currentItem?.unitPrice;
    if (resultingUnitPrice != null &&
        !(resultingUnitPrice * quantityValue).isFinite) {
      return const CartMutationResult(
        success: false,
        message: 'The item price is too large for this quantity.',
      );
    }

    final stockCheck =
        await _validateStockAvailability(productId, quantityValue);

    if (sessionGeneration != _sessionGeneration) {
      return const CartMutationResult(
        success: false,
        message: 'Your session changed. Start this sale again.',
      );
    }

    if (!stockCheck['available']) {
      return CartMutationResult(
        success: false,
        message: stockCheck['message'] as String? ?? 'Insufficient stock',
        currentStock: (stockCheck['currentStock'] as num?)?.toDouble() ?? 0,
      );
    }

    final updatedItems = state.items.map((item) {
      if (item.productId == productId) {
        final conversion = item.unitConversionFactor;
        final nextUnitPrice = unitPrice ?? item.unitPrice;
        return item.copyWith(
          quantity: quantityValue,
          unitPrice: nextUnitPrice,
          discount: _scaledDiscount(item,
              quantity: quantityValue, unitPrice: nextUnitPrice),
          notes: notes,
          saleUnit: saleUnit,
          saleQuantity: saleQuantity ??
              (conversion != null && conversion > 0
                  ? quantityValue / conversion
                  : item.saleQuantity),
          unitConversionFactor: unitConversionFactor,
        );
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
    return const CartMutationResult.success();
  }

  /// Moves a line by [delta] base units, keeping its price and sale unit.
  /// Going to zero or below removes the line.
  Future<CartMutationResult> changeQuantityBy(
      String productId, num delta) async {
    final sessionGeneration = _sessionGeneration;
    final index = state.items.indexWhere((i) => i.productId == productId);
    if (index < 0) {
      return const CartMutationResult(
        success: false,
        message: 'Item is not in the cart',
      );
    }
    final deltaValue = _quantityAtSupportedPrecision(delta);
    if (!deltaValue.isFinite) {
      return const CartMutationResult(
        success: false,
        message: 'Enter a valid quantity.',
      );
    }
    if (deltaValue == 0) return const CartMutationResult.success();

    final current = state.items[index];
    final currentStepQuantity = _quantityBeforeStepping(current);
    final wanted = _quantityAtSupportedPrecision(currentStepQuantity + deltaValue);
    if (wanted > 0 && wanted % 1 != 0 && !current.allowFractions) {
      return const CartMutationResult(
        success: false,
        message: 'This product is sold in whole units.',
      );
    }
    if (deltaValue > 0) {
      final stockCheck = await _validateStockAvailability(productId, wanted);
      if (sessionGeneration != _sessionGeneration) {
        return const CartMutationResult(
          success: false,
          message: 'Your session changed. Start this sale again.',
        );
      }
      if (!stockCheck['available']) {
        return CartMutationResult(
          success: false,
          message: stockCheck['message'] as String? ?? 'Insufficient stock',
          currentStock: (stockCheck['currentStock'] as num?)?.toDouble() ?? 0,
        );
      }
    }

    final latest = state.items.indexWhere((i) => i.productId == productId);
    if (latest < 0) return const CartMutationResult.success();
    final latestItem = state.items[latest];
    final latestConversionValue = latestItem.unitConversionFactor;
    final latestConversion = latestConversionValue != null &&
            latestConversionValue.isFinite &&
            latestConversionValue > 0
        ? latestConversionValue
        : 1.0;
    final newQuantity = _quantityAtSupportedPrecision(
        _quantityBeforeStepping(latestItem) + deltaValue);
    if (newQuantity <= 0) {
      removeItem(productId);
      return const CartMutationResult.success('Removed item');
    }
    if (!(latestItem.unitPrice * newQuantity).isFinite) {
      return const CartMutationResult(
        success: false,
        message: 'The item price is too large for this quantity.',
      );
    }

    final updatedItems = [...state.items];
    final item = updatedItems[latest];
    updatedItems[latest] = item.copyWith(
      quantity: newQuantity,
      discount: _scaledDiscount(item,
          quantity: newQuantity, unitPrice: item.unitPrice),
      saleQuantity: item.saleUnit != null
          ? newQuantity / latestConversion
          : item.saleQuantity,
    );
    state = state.copyWith(items: updatedItems);
    return const CartMutationResult.success();
  }

  /// Older cart rows could retain fractional sale-tier counts even when the
  /// product was configured for whole units. Normalize those rows to the
  /// nearest whole tier before applying a +/- step, so an old 1.08-box line
  /// steps from one box instead of carrying a stray base unit forward.
  double _quantityBeforeStepping(CartItem item) {
    if (item.allowFractions || item.saleUnit == null) return item.quantity;
    final conversion = item.unitConversionFactor;
    if (conversion == null || !conversion.isFinite || conversion <= 0) {
      return item.quantity;
    }
    final saleQuantity = item.saleQuantity;
    final tierCount = saleQuantity != null && saleQuantity.isFinite
        ? saleQuantity
        : item.quantity / conversion;
    return _quantityAtSupportedPrecision(tierCount.round() * conversion);
  }

  bool _sameSaleTier(CartItem item, String? saleUnit, double conversion) {
    final existingConversion = item.unitConversionFactor ?? 1;
    final sameConversion = (existingConversion - conversion).abs() < 0.000001;
    final sameUnit = item.saleUnit == saleUnit ||
        (sameConversion &&
            conversion == 1 &&
            (item.saleUnit == null || saleUnit == null));
    return sameUnit && sameConversion;
  }

  /// Preserve the line's effective discount rate when quantity or sale tier
  /// changes. Keeping the old absolute discount could make it exceed a new,
  /// smaller line total; dropping it would silently remove a cashier's price
  /// adjustment.
  double _scaledDiscount(CartItem item,
      {required double quantity, required double unitPrice}) {
    final oldGross = item.unitPrice * item.quantity;
    final newGross = unitPrice * quantity;
    if (!oldGross.isFinite ||
        !newGross.isFinite ||
        oldGross <= 0 ||
        newGross <= 0) {
      return 0;
    }
    final oldGrossSubunits = oldGross * 100;
    final newGrossSubunits = newGross * 100;
    if (!oldGrossSubunits.isFinite || !newGrossSubunits.isFinite) return 0;
    final oldGrossCents = oldGrossSubunits.round();
    final newGrossCents = newGrossSubunits.round();
    if (oldGrossCents <= 0 || newGrossCents <= 0) return 0;
    final rawDiscountCents = item.discount.isFinite ? item.discount * 100 : 0;
    final oldDiscountCents =
        rawDiscountCents.isFinite ? rawDiscountCents.round() : oldGrossCents;
    final boundedOldDiscount = oldDiscountCents.clamp(0, oldGrossCents);
    final nextDiscountCents =
        (boundedOldDiscount * newGrossCents / oldGrossCents).round();
    return nextDiscountCents.clamp(0, newGrossCents) / 100;
  }

  CartMutationResult updateItemDiscount(String productId, double discount,
      {String? reason}) {
    final index = state.items.indexWhere((item) => item.productId == productId);
    if (index < 0) {
      return const CartMutationResult(
        success: false,
        message: 'This item is no longer in the cart. Reopen it and try again.',
      );
    }
    if (!discount.isFinite || discount < 0) {
      return const CartMutationResult(
        success: false,
        message: 'The discount must be a valid amount of KES 0 or more.',
      );
    }

    final item = state.items[index];
    final lineTotal = item.unitPrice * item.quantity;
    if (!lineTotal.isFinite || lineTotal < 0 || discount > lineTotal) {
      return const CartMutationResult(
        success: false,
        message:
            'The adjusted price cannot be higher than the original line total.',
      );
    }
    final lineTotalCents = (lineTotal * 100).round();
    final discountCents = (discount * 100).round();
    if (discountCents > lineTotalCents) {
      return const CartMutationResult(
        success: false,
        message:
            'The adjusted price cannot be higher than the original line total.',
      );
    }

    final updatedItems = [...state.items];
    updatedItems[index] = item.copyWith(
      discount: discountCents / 100,
      notes: reason?.isNotEmpty == true ? reason : item.notes,
    );
    state = state.copyWith(items: updatedItems);
    return const CartMutationResult.success('Price updated');
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
  final notifier = CartNotifier();
  // A cart belongs to one cashier in one branch. Clear it on logout, staff
  // switch, or branch switch. Keep the notifier alive so an in-flight stock
  // check can be discarded by its session generation instead of writing into
  // a disposed StateNotifier.
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
