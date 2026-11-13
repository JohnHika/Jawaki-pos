import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Injectable transport keeps the live HTTPSMS call testable without sending a
/// real SMS or placing a credential on the test machine.
typedef HttpsmsTransport = Future<http.Response> Function(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
});

class HttpsmsSendResult {
  const HttpsmsSendResult({required this.statusCode, this.messageId});

  /// HTTPSMS accepted the request into its queue. This is not delivery proof.
  final int statusCode;
  final String? messageId;
}

class HttpsmsException implements Exception {
  const HttpsmsException(this.message, {this.outcomeUnknown = false});

  final String message;
  final bool outcomeUnknown;

  @override
  String toString() => message;
}

/// Sends one user-confirmed SMS through the shop's paired HTTPSMS phone.
/// Credentials are supplied from the device's secure store by the caller.
class HttpsmsService {
  HttpsmsService({HttpsmsTransport? transport})
      : _transport = transport ?? _post;

  static final Uri _sendUri = Uri.https('api.httpsms.com', '/v1/messages/send');
  static const Duration _timeout = Duration(seconds: 15);

  final HttpsmsTransport _transport;

  Future<HttpsmsSendResult> send({
    required String apiKey,
    required String from,
    required String to,
    required String content,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw const HttpsmsException(
        'Set up HTTPSMS in Settings before sending a text.',
      );
    }
    if (content.trim().isEmpty) {
      throw const HttpsmsException('The SMS message is empty.');
    }

    final sender = normalizePhoneNumber(from);
    final recipient = normalizePhoneNumber(to);
    final body = jsonEncode({
      'from': sender,
      'to': recipient,
      'content': content,
      // State the privacy behavior explicitly; HTTPSMS E2E encryption is not
      // enabled by default and has not been independently reviewed here.
      'encrypted': false,
    });

    late final http.Response response;
    try {
      response = await _transport(
        _sendUri,
        headers: {
          'x-api-key': normalizedKey,
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: body,
      ).timeout(_timeout);
    } on TimeoutException {
      // Do not blindly retry: HTTPSMS does not document idempotent retries,
      // and a timeout may happen after the message was queued.
      throw const HttpsmsException(
        'HTTPSMS did not confirm whether the SMS was queued. Check the HTTPSMS queue before trying again.',
        outcomeUnknown: true,
      );
    } catch (error) {
      if (error is HttpsmsException) rethrow;
      throw const HttpsmsException(
        'Could not confirm whether HTTPSMS queued the SMS. Check the HTTPSMS queue before trying again.',
        outcomeUnknown: true,
      );
    }

    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const HttpsmsException(
        'HTTPSMS returned an unexpected redirect. Counterbase did not forward the account key to another host. Check its queue before trying again.',
        outcomeUnknown: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        400 => 'HTTPSMS rejected the request. Check the sender and message.',
        401 => 'HTTPSMS rejected the account API key. Check it in Settings.',
        422 => 'HTTPSMS rejected the sender or recipient number.',
        500 =>
          'HTTPSMS returned a server error; the outcome is unknown. Check the HTTPSMS queue before trying again.',
        _ =>
          'HTTPSMS could not confirm the SMS outcome (HTTP ${response.statusCode}). Check the HTTPSMS queue before trying again.',
      };
      throw HttpsmsException(
        message,
        outcomeUnknown: !const {400, 401, 422}.contains(response.statusCode),
      );
    }

    return HttpsmsSendResult(
      statusCode: response.statusCode,
      messageId: _messageId(response.body),
    );
  }

  /// Converts a Kenyan national number to E.164 and accepts already
  /// international numbers only when they include a country-code prefix.
  static String normalizePhoneNumber(String raw) {
    final value = raw.trim();
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (value.startsWith('+')) {
      if (digits.length >= 8 &&
          digits.length <= 15 &&
          !digits.startsWith('0')) {
        return '+$digits';
      }
      throw const HttpsmsException(
        'Use a valid phone number with a country code, such as +2547…',
      );
    }
    if (digits.startsWith('00')) {
      final international = digits.substring(2);
      if (international.length >= 8 &&
          international.length <= 15 &&
          !international.startsWith('0')) {
        return '+$international';
      }
      throw const HttpsmsException(
        'Use a valid phone number with a country code, such as +2547…',
      );
    }
    if (digits.startsWith('254') && digits.length == 12) return '+$digits';
    if (digits.startsWith('0') && digits.length == 10) {
      return '+254${digits.substring(1)}';
    }
    if (digits.length == 9 &&
        (digits.startsWith('7') || digits.startsWith('1'))) {
      return '+254$digits';
    }
    throw const HttpsmsException(
      'Use a valid phone number with a country code, such as +2547…',
    );
  }

  static String? _messageId(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      if (data is Map) {
        return (data['id'] ?? data['message_id'])?.toString();
      }
      return (decoded['id'] ?? decoded['message_id'])?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(headers)
      ..body = body;
    final client = http.Client();
    try {
      final response = await client.send(request);
      return await http.Response.fromStream(response);
    } finally {
      client.close();
    }
  }
}
