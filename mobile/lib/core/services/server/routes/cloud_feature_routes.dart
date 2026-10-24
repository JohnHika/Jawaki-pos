import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;

/// Cloud-backed payment reconciliation and statement actions have no local
/// equivalent: they require the tenant's online data and provider APIs. Give
/// known routes an actionable response instead of a raw missing-route error.
class CloudFeatureRoutes {
  void addRoutes(Router r) {
    r.get('/api/v1/statements/settings', _statementsUnavailable);
    r.put('/api/v1/statements/settings', _statementsUnavailable);
    r.get('/api/v1/statements/preview', _statementsUnavailable);
    r.post('/api/v1/statements/links', _statementsUnavailable);
    r.get('/api/v1/statements/links', _statementsUnavailable);
    r.post(
        '/api/v1/statements/links/<id>/revoke', _statementsUnavailableWithId);
    r.get('/api/v1/statements/claims', _statementsUnavailable);
    r.post(
        '/api/v1/statements/claims/<id>/decide', _statementsUnavailableWithId);

    r.post('/api/v1/mpesa/parse', _mpesaUnavailable);
    r.post('/api/v1/mpesa/apply', _mpesaUnavailable);
    r.post('/api/v1/mpesa/ignore', _mpesaUnavailable);
    r.get('/api/v1/mpesa/history', _mpesaUnavailable);
  }

  Future<shelf.Response> _statementsUnavailable(shelf.Request request) async =>
      _response(
        'Statements need the online workspace',
        'Connect to the online Counterbase workspace to send statements and view customer replies. Your local sales and debts remain saved on this device.',
      );

  Future<shelf.Response> _statementsUnavailableWithId(
          shelf.Request request, String id) async =>
      _statementsUnavailable(request);

  Future<shelf.Response> _mpesaUnavailable(shelf.Request request) async =>
      _response(
        'M-Pesa matching needs the online workspace',
        'Connect to the online Counterbase workspace to match M-Pesa messages with debts. Your local sales and debts remain saved on this device.',
      );

  shelf.Response _response(String error, String message) => shelf.Response(
        503,
        body: jsonEncode({'error': error, 'message': message}),
        headers: {'content-type': 'application/json'},
      );
}
