class StockQuantityPresentation {
  final String primary;
  final String? secondary;
  final String? lastReceived;

  const StockQuantityPresentation({
    required this.primary,
    this.secondary,
    this.lastReceived,
  });
}

class ReceivedStockMetadata {
  final double quantity;
  final String unit;
  final double unitsPerQuantity;

  const ReceivedStockMetadata({
    required this.quantity,
    required this.unit,
    required this.unitsPerQuantity,
  });
}

String _formatStockNumber(num value) {
  final number = value.toDouble();
  if (number == number.roundToDouble()) {
    return number.toStringAsFixed(0);
  }
  return number
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

StockQuantityPresentation buildStockQuantityPresentation({
  required num baseQuantity,
  required String baseUnit,
  String? preferredUnit,
  num? unitsPerPreferredUnit,
  num? lastReceivedQuantity,
}) {
  final normalizedBaseUnit =
      baseUnit.trim().isEmpty ? 'piece' : baseUnit.trim();
  final normalizedPreferredUnit = preferredUnit?.trim();
  final conversion = unitsPerPreferredUnit?.toDouble();
  final canUsePreferredUnit = normalizedPreferredUnit != null &&
      normalizedPreferredUnit.isNotEmpty &&
      conversion != null &&
      conversion > 0 &&
      normalizedPreferredUnit.toLowerCase() != normalizedBaseUnit.toLowerCase();

  if (!canUsePreferredUnit) {
    return StockQuantityPresentation(
      primary: '${_formatStockNumber(baseQuantity)} $normalizedBaseUnit',
      lastReceived: lastReceivedQuantity == null
          ? null
          : 'Last received: ${_formatStockNumber(lastReceivedQuantity)} $normalizedBaseUnit',
    );
  }

  return StockQuantityPresentation(
    primary:
        '${_formatStockNumber(baseQuantity.toDouble() / conversion)} $normalizedPreferredUnit',
    secondary: '${_formatStockNumber(baseQuantity)} $normalizedBaseUnit',
    lastReceived: lastReceivedQuantity == null
        ? null
        : 'Last received: ${_formatStockNumber(lastReceivedQuantity)} $normalizedPreferredUnit',
  );
}

ReceivedStockMetadata? parseReceivedStockNote(String? notes) {
  if (notes == null || notes.trim().isEmpty) return null;

  final metadataMatch = RegExp(
    r'\[Receipt metadata: quantity=([0-9]+(?:\.[0-9]+)?); unit=([^;]+); unitsPerQuantity=([0-9]+(?:\.[0-9]+)?)\]',
    caseSensitive: false,
  ).firstMatch(notes);
  if (metadataMatch != null) {
    final quantity = double.tryParse(metadataMatch.group(1)!);
    final unitsPerQuantity = double.tryParse(metadataMatch.group(3)!);
    String unit;
    try {
      unit = Uri.decodeComponent(metadataMatch.group(2)!).trim();
    } catch (_) {
      unit = metadataMatch.group(2)!.trim();
    }
    if (quantity != null &&
        quantity > 0 &&
        unitsPerQuantity != null &&
        unitsPerQuantity > 0 &&
        unit.isNotEmpty) {
      return ReceivedStockMetadata(
        quantity: quantity,
        unit: unit,
        unitsPerQuantity: unitsPerQuantity,
      );
    }
  }

  final match = RegExp(
    r'^Received\s+([0-9]+(?:\.[0-9]+)?)\s+(.+?)\s+=\s+([0-9]+(?:\.[0-9]+)?)\s+(.+?)(?:\.|$)',
    caseSensitive: false,
  ).firstMatch(notes.trim());
  if (match == null) return null;

  final receivedQuantity = double.tryParse(match.group(1)!);
  final baseQuantity = double.tryParse(match.group(3)!);
  final unit = match.group(2)?.trim();
  if (receivedQuantity == null ||
      receivedQuantity <= 0 ||
      baseQuantity == null ||
      baseQuantity <= 0 ||
      unit == null ||
      unit.isEmpty) {
    return null;
  }

  return ReceivedStockMetadata(
    quantity: receivedQuantity,
    unit: unit,
    unitsPerQuantity: baseQuantity / receivedQuantity,
  );
}
