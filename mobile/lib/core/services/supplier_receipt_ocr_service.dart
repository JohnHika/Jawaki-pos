import 'dart:io';
import 'dart:math';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class SupplierReceiptScan {
  final String imagePath;
  final String rawText;
  final String suggestedSupplierName;
  final String? invoiceNumber;
  final double totalAmount;
  final List<SupplierReceiptLineItem> items;
  final String summary;

  const SupplierReceiptScan({
    required this.imagePath,
    required this.rawText,
    required this.suggestedSupplierName,
    required this.invoiceNumber,
    required this.totalAmount,
    required this.items,
    required this.summary,
  });
}

class SupplierReceiptLineItem {
  final String name;
  final String? sku;
  final double quantity;
  final String unit;
  final double unitCost;
  final double lineTotal;
  final double confidence;
  final String rawText;

  const SupplierReceiptLineItem({
    required this.name,
    this.sku,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.lineTotal,
    required this.confidence,
    required this.rawText,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'sku': sku,
        'quantity': quantity,
        'unit': unit,
        'unitCost': unitCost,
        'lineTotal': lineTotal,
        'confidence': confidence,
        'rawText': rawText,
      };
}

class SupplierReceiptOcrService {
  static final RegExp _moneyRegex =
      RegExp(r'(?<!\d)(\d{1,3}(?:[, ]\d{3})*|\d+)(?:\.\d{1,2})?(?!\d)');
  static final RegExp _invoiceRegex = RegExp(
      r'(invoice|receipt|ref|no\.?|number)\s*[:#-]?\s*([A-Z0-9\-/]{3,})',
      caseSensitive: false);
  static final Set<String> _noiseWords = {
    'total',
    'subtotal',
    'balance',
    'amount',
    'paid',
    'change',
    'cash',
    'mpesa',
    'vat',
    'tax',
    'date',
    'time',
    'invoice',
    'receipt',
    'thank',
    'served',
  };

  Future<SupplierReceiptScan> scan(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized =
          await recognizer.processImage(InputImage.fromFile(image));
      final rawText = recognized.text.trim();
      final lines = rawText
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final invoiceNumber = _extractInvoiceNumber(lines);
      final supplierName = _extractSupplierName(lines);
      final items = _extractItems(lines);
      final total = _extractTotal(lines, items);

      return SupplierReceiptScan(
        imagePath: image.path,
        rawText: rawText,
        suggestedSupplierName: supplierName,
        invoiceNumber: invoiceNumber,
        totalAmount: total,
        items: items,
        summary: _buildSummary(supplierName, items, total, invoiceNumber),
      );
    } finally {
      await recognizer.close();
    }
  }

  String _extractSupplierName(List<String> lines) {
    for (final line in lines.take(6)) {
      final cleaned =
          line.replaceAll(RegExp(r'[^A-Za-z0-9 &().,-]'), '').trim();
      if (cleaned.length >= 3 &&
          !_looksLikeNoise(cleaned) &&
          !_containsMoney(cleaned)) {
        return cleaned;
      }
    }
    return 'Unknown Supplier';
  }

  String? _extractInvoiceNumber(List<String> lines) {
    for (final line in lines.take(15)) {
      final match = _invoiceRegex.firstMatch(line);
      if (match != null) return match.group(2);
    }
    return null;
  }

  List<SupplierReceiptLineItem> _extractItems(List<String> lines) {
    final items = <SupplierReceiptLineItem>[];
    for (final line in lines) {
      if (_looksLikeNoise(line) || !_containsMoney(line)) continue;
      final amounts = _numbers(line);
      if (amounts.isEmpty) continue;

      final name = _extractItemName(line);
      if (name.length < 2 || _looksLikeNoise(name)) continue;

      double quantity = 1;
      double lineTotal = amounts.last;
      double unitCost = lineTotal;

      if (amounts.length >= 3 && amounts.first > 0 && amounts.first <= 10000) {
        quantity = amounts.first;
        unitCost = amounts[amounts.length - 2];
        lineTotal = amounts.last;
      } else if (amounts.length == 2 &&
          amounts.first > 0 &&
          amounts.first <= 1000 &&
          amounts.last > amounts.first) {
        quantity = amounts.first;
        lineTotal = amounts.last;
        unitCost = lineTotal / max(quantity, 1);
      }

      items.add(SupplierReceiptLineItem(
        name: name,
        quantity: quantity,
        unit: 'piece',
        unitCost: unitCost,
        lineTotal: lineTotal,
        confidence: amounts.length >= 2 ? 0.72 : 0.55,
        rawText: line,
      ));
    }

    final seen = <String>{};
    return items
        .where((item) {
          final key =
              '${item.name.toLowerCase()}:${item.lineTotal.toStringAsFixed(2)}';
          if (seen.contains(key)) return false;
          seen.add(key);
          return true;
        })
        .take(30)
        .toList();
  }

  double _extractTotal(
      List<String> lines, List<SupplierReceiptLineItem> items) {
    for (final line in lines.reversed) {
      if (RegExp(r'\b(total|balance|amount due|grand total)\b',
              caseSensitive: false)
          .hasMatch(line)) {
        final nums = _numbers(line);
        if (nums.isNotEmpty) return nums.last;
      }
    }
    return items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  }

  String _extractItemName(String line) {
    var name = line
        .replaceAll(_moneyRegex, ' ')
        .replaceAll(
            RegExp(r'\b(qty|quantity|pcs|x|kes|ksh)\b', caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9 &()./-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (name.length > 48) name = name.substring(0, 48).trim();
    return name;
  }

  bool _containsMoney(String line) =>
      _moneyRegex.hasMatch(line.replaceAll(',', ''));

  List<double> _numbers(String line) => _moneyRegex
      .allMatches(line.replaceAll(',', ''))
      .map((match) => double.tryParse(match.group(0)!.replaceAll(' ', '')))
      .whereType<double>()
      .toList();

  bool _looksLikeNoise(String line) {
    final lower = line.toLowerCase();
    if (lower.length < 2) return true;
    return _noiseWords.any((word) => RegExp('\\b$word\\b').hasMatch(lower));
  }

  String _buildSummary(String supplier, List<SupplierReceiptLineItem> items,
      double total, String? invoiceNumber) {
    final invoice = invoiceNumber == null ? '' : ' Invoice $invoiceNumber.';
    final topItems = items.take(3).map((item) => item.name).join(', ');
    final itemSummary = topItems.isEmpty
        ? 'No clear line items detected.'
        : 'Detected ${items.length} item(s): $topItems.';
    return '$supplier.$invoice $itemSummary Estimated total KES ${total.toStringAsFixed(0)}.';
  }
}
