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

    // These are the current merchant-specific Paystack endpoints. Register
    // them explicitly so phone-server mode never falls through to a raw 404.
    r.get('/api/v1/merchant-payments/account', _handleMerchantPaymentStub);
    r.get('/api/v1/merchant-payments/banks', _handleMerchantPaymentStub);
    r.get('/api/v1/merchant-payments/charges', _handleMerchantPaymentStub);
    r.post('/api/v1/merchant-payments/account', _handleMerchantPaymentStub);
    r.post('/api/v1/merchant-payments/mpesa', _handleMerchantPaymentStub);
    r.get('/api/v1/merchant-payments/mpesa/<reference>',
        _handleMerchantPaymentStatusStub);
    r.post('/api/v1/merchant-payments/receivables/mpesa',
        _handleMerchantPaymentStub);
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

  Future<shelf.Response> _handleMerchantPaymentStub(
      shelf.Request request) async {
    return _merchantPaymentsNotAvailable();
  }

  Future<shelf.Response> _handleMerchantPaymentStatusStub(
      shelf.Request request, String reference) async {
    return _merchantPaymentsNotAvailable();
  }

  Future<shelf.Response> _merchantPaymentsNotAvailable() async {
    return shelf.Response(
      503,
      body: jsonEncode({
        'error': 'Merchant payments need the online workspace',
        'message':
            'Connect to the online Counterbase workspace to set up Paystack or collect customer M-Pesa payments. Cash and credit sales remain available on this device.',
        'provider': 'Paystack',
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<shelf.Response> _paymentNotAvailable(String provider) async {
    return shelf.Response(
      503,
      body: jsonEncode({
        'error': '$provider requires internet access',
        'message': 'Connect to the online Counterbase workspace to use this payment provider. Cash and credit sales remain available on this device.',
        'provider': provider,
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
