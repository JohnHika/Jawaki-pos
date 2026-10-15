import 'dart:convert';
import 'dart:io';

import '../network/api_client.dart';
import 'supplier_receipt_ocr_service.dart';

/// Thrown when the vision model determines the scanned image isn't a
/// receipt/invoice/delivery note at all — distinct from a scan failure
/// (network/gateway unavailable), which falls back to on-device OCR
/// instead of surfacing this specific rejection to the user.
class NotAReceiptException implements Exception {
  const NotAReceiptException(this.reason);
  final String reason;

  @override
  String toString() => reason;
}

/// Thrown when the AI could not be reached or could not read the photo, so
/// the caller should fall back to on-device OCR (not tell the user their
/// photo "isn't a receipt").
class ReceiptAiUnavailableException implements Exception {
  const ReceiptAiUnavailableException([this.message = 'Axon AI is unavailable']);
  final String message;

  @override
  String toString() => message;
}

/// AI vision parsing of a supplier receipt photo, via the backend's
/// /ai/receipts/scan endpoint (which itself calls the Axon AI gateway).
/// Requires connectivity and an active AI subscription for the branch —
/// callers should fall back to SupplierReceiptOcrService when this fails
/// for any reason other than NotAReceiptException.
class ReceiptVisionService {
  ReceiptVisionService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Reads a receipt photo straight from disk — sent inline as base64, so no
  /// upload step is needed and the AI sees exactly what the camera took.
  Future<SupplierReceiptScan> scanFile(File image, {String? branchId}) async {
    final bytes = await image.readAsBytes();
    final result = await _apiClient.scanReceiptImage(
      imageBase64: base64Encode(bytes),
      branchId: branchId,
    );
    return parse(result, imagePath: image.path);
  }

  Future<SupplierReceiptScan> scan({
    required String imageUrl,
    String? branchId,
  }) async {
    final result = await _apiClient.scanReceiptImage(
      imageUrl: imageUrl,
      branchId: branchId,
    );
    return parse(result, imagePath: imageUrl);
  }

  /// Turns the backend's ParsedReceiptResult JSON into a scan. Exposed for
  /// tests.
  SupplierReceiptScan parse(Map<String, dynamic> result,
      {required String imagePath}) {
    final isReceipt = result['isReceipt'] as bool? ?? false;
    if (!isReceipt) {
      // 'unavailable' / unreadable output means the AI never actually looked
      // at the photo — that's a fallback case, not a verdict on the image.
      final model = result['model'] as String?;
      final reason = result['rejectionReason'] as String? ??
          'This image does not appear to be a receipt.';
      if (model == 'unavailable' || reason.startsWith("Couldn't read")) {
        throw ReceiptAiUnavailableException(reason);
      }
      throw NotAReceiptException(reason);
    }

    final rawItems = (result['items'] as List?) ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((item) => SupplierReceiptLineItem(
              name: (item['name'] as String?)?.trim() ?? '',
              quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
              unit: (item['unit'] as String?)?.trim().isNotEmpty == true
                  ? (item['unit'] as String).trim()
                  : 'piece',
              unitCost: (item['unitCost'] as num?)?.toDouble() ?? 0,
              lineTotal: (item['lineTotal'] as num?)?.toDouble() ?? 0,
              confidence: 1.0,
              rawText: '',
            ))
        .where((item) => item.name.isNotEmpty)
        .toList();

    final supplierName = (result['supplierName'] as String?)?.trim();
    final invoiceNumber = (result['invoiceNumber'] as String?)?.trim();
    final totalAmount = (result['totalAmount'] as num?)?.toDouble() ??
        items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final aiSummary = (result['summary'] as String?)?.trim();

    final topItems = items.take(3).map((item) => item.name).join(', ');
    final fallbackSummary = [
      if (supplierName != null && supplierName.isNotEmpty) supplierName,
      if (invoiceNumber != null && invoiceNumber.isNotEmpty)
        'Invoice $invoiceNumber.',
      topItems.isEmpty
          ? 'No clear line items detected.'
          : 'Detected ${items.length} item(s): $topItems.',
      'Estimated total KES ${totalAmount.toStringAsFixed(0)}.',
    ].join(' ');

    return SupplierReceiptScan(
      imagePath: imagePath,
      rawText: (result['rawModelText'] as String?) ?? '',
      suggestedSupplierName: supplierName != null && supplierName.isNotEmpty
          ? supplierName
          : 'Unknown Supplier',
      invoiceNumber: invoiceNumber,
      totalAmount: totalAmount,
      items: items,
      summary: aiSummary != null && aiSummary.isNotEmpty
          ? aiSummary
          : fallbackSummary,
      readByAi: true,
      documentType: (result['documentType'] as String?)?.trim(),
      paymentMethod: (result['paymentMethod'] as String?)?.trim(),
    );
  }
}
