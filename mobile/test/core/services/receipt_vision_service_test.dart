import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/receipt_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoNetworkApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('parse() must not touch the network');
}

void main() {
  final service = ReceiptVisionService(apiClient: _NoNetworkApiClient());

  test('reads supplier, items, document type and payment method', () {
    final scan = service.parse({
      'isReceipt': true,
      'documentType': 'supplier_invoice',
      'summary': 'Supplier invoice from Fresh Farm for 2 items.',
      'supplierName': 'Fresh Farm Distributors',
      'invoiceNumber': 'INV-8841',
      'paymentMethod': 'credit',
      'items': [
        {
          'name': 'Maize Flour 2kg',
          'quantity': 10,
          'unit': 'carton',
          'unitCost': 1450,
          'lineTotal': 14500,
        },
        {'name': '', 'quantity': 1},
      ],
      'totalAmount': 14500,
    }, imagePath: '/tmp/a.jpg');

    expect(scan.readByAi, isTrue);
    expect(scan.documentTypeLabel, 'Supplier invoice');
    expect(scan.paymentMethod, 'credit');
    expect(scan.suggestedSupplierName, 'Fresh Farm Distributors');
    expect(scan.summary, 'Supplier invoice from Fresh Farm for 2 items.');
    expect(scan.items, hasLength(1));
    expect(scan.items.single.unit, 'carton');
    expect(scan.totalAmount, 14500);
  });

  test('a photo the AI says is not a receipt is rejected with its reason', () {
    expect(
      () => service.parse({
        'isReceipt': false,
        'rejectionReason': 'This is a photo of a dog.',
        'model': 'glm',
      }, imagePath: 'x'),
      throwsA(isA<NotAReceiptException>()
          .having((e) => e.reason, 'reason', 'This is a photo of a dog.')),
    );
  });

  test('an unavailable AI is a fallback case, not "not a receipt"', () {
    expect(
      () => service.parse({
        'isReceipt': false,
        'rejectionReason': 'Scan service unavailable — please enter details manually.',
        'model': 'unavailable',
      }, imagePath: 'x'),
      throwsA(isA<ReceiptAiUnavailableException>()),
    );
    expect(
      () => service.parse({
        'isReceipt': false,
        'rejectionReason': "Couldn't read this receipt clearly — please enter details manually.",
        'model': 'glm',
      }, imagePath: 'x'),
      throwsA(isA<ReceiptAiUnavailableException>()),
    );
  });
}
