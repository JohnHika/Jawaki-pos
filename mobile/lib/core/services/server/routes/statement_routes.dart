import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' show Router;

/// Statements and customer replies are cloud-backed features. Phone-server
/// mode has no safe local equivalent because customer links and replies live
/// in the tenant's online workspace. Return an actionable API response rather
/// than Shelf's unhelpful "Not Found" page for these known endpoints.
class StatementRoutes {
  void addRoutes(Router r) {
    r.get('/api/v1/statements/settings', _notAvailable);
    r.put('/api/v1/statements/settings', _notAvailable);
    r.get('/api/v1/statements/preview', _notAvailable);
    r.post('/api/v1/statements/links', _notAvailable);
    r.get('/api/v1/statements/links', _notAvailable);
    r.post('/api/v1/statements/links/<id>/revoke', _notAvailableWithId);
    r.get('/api/v1/statements/claims', _notAvailable);
    r.post('/api/v1/statements/claims/<id>/decide', _notAvailableWithId);
  }

  Future<shelf.Response> _notAvailable(shelf.Request request) async =>
      _response();

  Future<shelf.Response> _notAvailableWithId(
          shelf.Request request, String id) async =>
      _response();

  shelf.Response _response() => shelf.Response(
        503,
        body: jsonEncode({
          'error': 'Statements need the online workspace',
          'message':
              'Connect to the online Counterbase workspace to send statements and view customer replies. Your local sales and debts remain saved on this device.',
        }),
        headers: {'content-type': 'application/json'},
      );
}
