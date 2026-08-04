/// Unified Pricing Service
///
/// Handles unit type pricing calculations for POS system:
/// - Base price (per piece/unit)
/// - Secondary unit (e.g., dozen, box) with quantity per unit
/// - Tertiary unit (e.g., carton) with quantity per unit
/// - Branch-specific price overrides
/// - Manual price adjustments during checkout
library;

class UnitPriceInfo {
  final String unit;
  final double price;
  final double? quantityPerUnit; // e.g., 12 for dozen
  final String? unitTypeLabel; // e.g., "Dozen", "Box"

  UnitPriceInfo({
    required this.unit,
    required this.price,
    this.quantityPerUnit,
    this.unitTypeLabel,
  });

  /// Convert price to per-unit basis
  double get perUnitPrice {
    if (quantityPerUnit != null && quantityPerUnit! > 0) {
      return price / quantityPerUnit!;
    }
    return price;
  }

  /// Format price with currency
  String formatPrice({String prefix = 'KES '}) =>
      '$prefix${price.toStringAsFixed(0)}';

  @override
  String toString() {
    if (quantityPerUnit != null && quantityPerUnit! > 0) {
      return '$unitTypeLabel @ $formatPrice (${perUnitPrice.toStringAsFixed(2)} per $unit)';
    }
    return '$unit @ $formatPrice';
  }
}

class PricingService {
  /// Get unit price info from product data
  static UnitPriceInfo getUnitPriceInfo(Map<String, dynamic> product) {
    final unit = product['unit'] as String? ?? 'piece';
    final basePrice = (product['basePrice'] as num?)?.toDouble() ?? 0;
    final price = (product['price'] as num?)?.toDouble() ?? basePrice;

    return UnitPriceInfo(
      unit: unit,
      price: price,
      unitTypeLabel: unit[0].toUpperCase() + unit.substring(1),
    );
  }

  /// Get all pricing tiers for a product — the base unit plus any number
  /// of bulk-selling tiers (dozen, carton, pallet, ...) the shop owner has
  /// configured. No cap: however many tiers exist in `pricingTiers` are
  /// all returned.
  static List<UnitPriceInfo> getAllPricingTiers(Map<String, dynamic> product) {
    final tiers = <UnitPriceInfo>[];

    final basePrice = (product['basePrice'] as num?)?.toDouble() ?? 0;
    final price = (product['price'] as num?)?.toDouble() ?? basePrice;

    // Base tier (per unit)
    tiers.add(
      UnitPriceInfo(
        unit: product['unit'] as String? ?? 'piece',
        price: price,
        unitTypeLabel: 'Unit',
      ),
    );

    final rawTiers = product['pricingTiers'];
    if (rawTiers is List) {
      final sorted = rawTiers.whereType<Map>().toList()
        ..sort((a, b) {
          final aOrder = (a['sortOrder'] as num?)?.toInt() ?? 0;
          final bOrder = (b['sortOrder'] as num?)?.toInt() ?? 0;
          return aOrder.compareTo(bOrder);
        });

      for (final tier in sorted) {
        final unit = tier['unit'] as String?;
        final quantityPerUnit = (tier['quantityPerUnit'] as num?)?.toDouble();
        final tierPrice = (tier['price'] as num?)?.toDouble();
        if (unit == null ||
            unit.isEmpty ||
            quantityPerUnit == null ||
            quantityPerUnit <= 0 ||
            tierPrice == null) {
          continue;
        }
        tiers.add(
          UnitPriceInfo(
            unit: unit,
            price: tierPrice,
            quantityPerUnit: quantityPerUnit,
            unitTypeLabel: unit[0].toUpperCase() + unit.substring(1),
          ),
        );
      }
    }

    return tiers;
  }

  /// Calculate total price for quantity with unit type
  static double calculateTotalPrice({
    required double unitPrice,
    required double quantity,
    String? unitType,
    double? quantityPerUnit,
  }) {
    if (unitType != null && quantityPerUnit != null && quantityPerUnit > 0) {
      // Convert bulk quantity to base units
      final baseUnits = quantity * quantityPerUnit;
      return baseUnits * unitPrice;
    }
    return quantity * unitPrice;
  }

  /// Format price for display
  static String formatPrice(double price, {String prefix = 'KES '}) {
    return '$prefix${price.toStringAsFixed(0)}';
  }

  /// Parse price string to double
  static double parsePrice(String priceStr) {
    final cleaned = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }
}

/// Price adjustment model for manual override during checkout
class PriceAdjustment {
  final String itemId;
  final double originalPrice;
  final double adjustedPrice;
  final String reason;
  final DateTime timestamp;

  PriceAdjustment({
    required this.itemId,
    required this.originalPrice,
    required this.adjustedPrice,
    this.reason = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'originalPrice': originalPrice,
    'adjustedPrice': adjustedPrice,
    'reason': reason,
    'timestamp': timestamp.toIso8601String(),
  };

  factory PriceAdjustment.fromJson(Map<String, dynamic> json) =>
      PriceAdjustment(
        itemId: json['itemId'] as String,
        originalPrice: (json['originalPrice'] as num?)?.toDouble() ?? 0,
        adjustedPrice: (json['adjustedPrice'] as num?)?.toDouble() ?? 0,
        reason: json['reason'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
      );

  PriceAdjustment copyWith({double? adjustedPrice, String? reason}) {
    return PriceAdjustment(
      itemId: itemId,
      originalPrice: originalPrice,
      adjustedPrice: adjustedPrice ?? this.adjustedPrice,
      reason: reason ?? this.reason,
      timestamp: timestamp,
    );
  }
}
