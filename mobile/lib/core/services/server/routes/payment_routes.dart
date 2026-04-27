import 'dart:convert';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;

/// Payment route stubs for phone server mode.
///
/// Real M-Pesa/PesaPal/TouristTap payments require internet.
/// For local/offline mode, we return a helpful message.
class PaymentRoutes {
  PaymentRoutes();

  void addRoutes(Router r) {
    r.post('/api/v1/payments/mpesa/stkpush', _handleMpesaStub);
    r.get('/api/v1/payments/mpesa/status/<checkoutRequestId>', _handleMpesaStatusStub);
    r.post('/api/v1/payments/pesapal/initiate', _handlePesapalStub);
    r.post('/api/v1/payments/touristtap/initiate', _handleTouristTapStub);
  }

  Future<shelf.Response> _handleMpesaStub(shelf.Request request) async {
    return _paymentNotAvailable('M-Pesa');
  }

  Future<shelf.Response> _handleMpesaStatusStub(shelf.Request request, String checkoutRequestId) async {
    return _paymentNotAvailable('M-Pesa');
  }

  Future<shelf.Response> _handlePesapalStub(shelf.Request request) async {
    return _paymentNotAvailable('PesaPal');
  }

  Future<shelf.Response> _handleTouristTapStub(shelf.Request request) async {
    return _paymentNotAvailable('TouristTap');
  }

  Future<shelf.Response> _paymentNotAvailable(String provider) async {
    return shelf.Response(
      503,
      body: jsonEncode({
        'error': '$provider requires internet access',
        'message': 'Please process this payment on the server phone or use cash/credit payment methods instead.',
        'provider': provider,
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
