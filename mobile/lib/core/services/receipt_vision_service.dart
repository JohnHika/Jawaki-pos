import 'dart:convert';
import 'dart:io';

import 'axon_gateway_client.dart';
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
  const ReceiptAiUnavailableException(
      [this.message = 'Axon AI is unavailable']);
  final String message;

  @override
  String toString() => message;
}

/// Receipt photos are analyzed only through the owner-keyed Axon Gateway.
/// The caller must review the suggested invoice details before saving them.
class ReceiptVisionService {
  ReceiptVisionService({AxonGatewayClient? gateway})
      : _gateway = gateway ?? AxonGatewayClient();

  final AxonGatewayClient _gateway;

  Future<SupplierReceiptScan> scanFile(File image, {String? branchId}) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > AxonGatewayClient.maxVisionImageBytes) {
        throw const ReceiptAiUnavailableException(
          'This image is too large to analyze. Choose a smaller image.',
        );
      }
      final response = await _gateway.vision(
        prompt: 'Read this supplier receipt, invoice, or delivery note. Return '
            'only a valid JSON object with these fields: isReceipt (boolean), '
            'documentType (string), supplierName (string or null), '
            'invoiceNumber (string or null), totalAmount (number), '
            'paymentMethod (string or null), summary (string), and items '
            '(array of objects with name, quantity, unit, unitCost, and '
            'lineTotal). Use null or an empty array when a value is not '
            'visible. Do not guess missing amounts. If this is not a supplier '
            'receipt, invoice, or delivery note, set isReceipt to false.',
        imageBase64: base64Encode(bytes),
        maxTokens: 1600,
      );
      final normalized = response
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) {
        throw const ReceiptAiUnavailableException(
          'Axon AI returned unreadable receipt details. Try again or enter them manually.',
        );
      }
      return parse(decoded.cast<String, dynamic>(), imagePath: image.path);
    } on AxonGatewayException catch (error) {
      throw ReceiptAiUnavailableException(error.message);
    } on FormatException {
      throw const ReceiptAiUnavailableException(
        'Axon AI returned unreadable receipt details. Try again or enter them manually.',
      );
    } on FileSystemException {
      throw const ReceiptAiUnavailableException(
        'Could not open this image. Choose it again or enter the receipt manually.',
      );
    }
  }

  Future<SupplierReceiptScan> scan({
    required String imageUrl,
    String? branchId,
  }) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || (uri.scheme.isNotEmpty && uri.scheme != 'file')) {
      throw const ReceiptAiUnavailableException(
        'Only an image stored on this device can be analyzed. Remote image links are not fetched.',
      );
    }
    return scanFile(
      File(uri.scheme == 'file' ? uri.toFilePath() : imageUrl),
      branchId: branchId,
    );
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
