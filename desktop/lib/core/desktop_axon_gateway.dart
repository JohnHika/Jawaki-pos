import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'desktop_workspace.dart';

class DesktopAxonGatewayFailure implements Exception {
  const DesktopAxonGatewayFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Direct, fixed-host client for the owner's Axon POS assistant.
/// Credentials are read from secure storage for every request and are never
/// included in logs or error messages.
class DesktopAxonGatewayClient {
  DesktopAxonGatewayClient(this.session);

  final DesktopSession session;
  static final Uri _chatUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/chat',
  );
  static final Uri _streamChatUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/chat/stream',
  );
  static final Uri _visionUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/vision',
  );
  static const _timeout = Duration(seconds: 45);
  static const _maxResponseBytes = 2 * 1024 * 1024;
  static const maxVisionImageBytes = 12 * 1024 * 1024;

  Future<Map<String, dynamic>> chatTurn({
    required String system,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    int maxTokens = 1200,
  }) async {
    return _post(_chatUri, {
      'system': system,
      'messages': messages,
      'tools': tools,
      'max_tokens': maxTokens,
      'stream': false,
    });
  }

  /// Streams one Anthropic-compatible agent turn. The callback receives the
  /// accumulated visible text; tool-use blocks are returned as structured
  /// content once the stream finishes.
  Future<Map<String, dynamic>> chatTurnStream({
    required String system,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    int maxTokens = 1200,
    void Function(String accumulatedText)? onText,
  }) async {
    return _streamChat({
      'system': system,
      'messages': messages,
      'tools': tools,
      'max_tokens': maxTokens,
      'stream': true,
    }, onText: onText);
  }

  Future<String> vision({
    required String prompt,
    required String imageBase64,
    int maxTokens = 1200,
  }) async {
    if (imageBase64.isEmpty ||
        imageBase64.length > maxVisionImageBytes * 4 ~/ 3 + 8) {
      throw const DesktopAxonGatewayFailure(
        'Choose an image smaller than 12 MB before sending it to Axon AI.',
      );
    }
    final result = await _post(_visionUri, {
      'prompt': prompt,
      'image_base64': imageBase64,
      'max_tokens': maxTokens,
    });
    final response = (result['response'] ?? '').toString().trim();
    if (response.isEmpty) {
      throw const DesktopAxonGatewayFailure(
        'Axon AI could not read this image. Try another image.',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _post(Uri uri, Map<String, dynamic> body) async {
    String? key;
    try {
      key = await session.getAxonGatewayKey();
    } catch (_) {
      throw const DesktopAxonGatewayFailure(
        'This computer’s secure credential store is unavailable. No request was sent.',
      );
    }
    if (key == null || key.trim().isEmpty) {
      throw const DesktopAxonGatewayFailure(
        'Add the owner-issued Axon Gateway key in Settings before using AI. No prompt or shop data was sent.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(uri).timeout(_timeout);
      // Never forward the owner-issued bearer key to a redirect target.
      // Axon Gateway is a fixed endpoint; a redirect is an integration error.
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${key.trim()}',
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      if (response.contentLength > _maxResponseBytes) {
        throw const DesktopAxonGatewayFailure(
          'Axon AI returned an unexpectedly large response. Try a shorter question.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _statusFailure(response.statusCode);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_timeout)) {
        if (bytes.length + chunk.length > _maxResponseBytes) {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an unexpectedly large response. Try a shorter question.',
          );
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const DesktopAxonGatewayFailure(
          'Axon AI returned an invalid response. Please try again.',
        );
      }
      return decoded.cast<String, dynamic>();
    } on DesktopAxonGatewayFailure {
      rethrow;
    } on TimeoutException {
      throw const DesktopAxonGatewayFailure(
        'Axon AI took too long to respond. Check the connection and try again.',
      );
    } on SocketException {
      throw const DesktopAxonGatewayFailure(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } on FormatException {
      throw const DesktopAxonGatewayFailure(
        'Axon AI returned an invalid response. Please try again.',
      );
    } on HttpException {
      throw const DesktopAxonGatewayFailure(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } catch (_) {
      throw const DesktopAxonGatewayFailure(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _streamChat(
    Map<String, dynamic> body, {
    void Function(String accumulatedText)? onText,
  }) async {
    String? key;
    try {
      key = await session.getAxonGatewayKey();
    } catch (_) {
      throw const DesktopAxonGatewayFailure(
        'This computer’s secure credential store is unavailable. No request was sent.',
      );
    }
    if (key == null || key.trim().isEmpty) {
      throw const DesktopAxonGatewayFailure(
        'Add the owner-issued Axon Gateway key in Settings before using AI. No prompt or shop data was sent.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(_streamChatUri).timeout(_timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${key.trim()}',
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/event-stream, application/json',
      );
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const DesktopAxonGatewayFailure(
          'Axon AI returned an unexpected redirect. The saved key was not forwarded. Contact the account owner.',
        );
      }
      if (response.contentLength > _maxResponseBytes) {
        throw const DesktopAxonGatewayFailure(
          'Axon AI returned an unexpectedly large response. Try a shorter question.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _statusFailure(response.statusCode);
      }

      final blocks = <int, Map<String, dynamic>>{};
      final toolInput = <int, StringBuffer>{};
      final visibleText = StringBuffer();
      String? stopReason;
      String? messageId;
      String? model;
      Map<String, dynamic> usage = <String, dynamic>{};
      Map<String, dynamic>? completePayload;
      var receivedBytes = 0;
      var eventName = '';
      final eventData = StringBuffer();

      void emitEvent() {
        if (eventData.isEmpty) {
          eventName = '';
          return;
        }
        final raw = eventData.toString();
        eventData.clear();
        final currentEventName = eventName;
        eventName = '';
        if (raw == '[DONE]') return;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) return;
        final event = Map<String, dynamic>.from(decoded);
        final type = (event['type'] ?? currentEventName).toString();
        if (event['content'] is List && event.containsKey('stop_reason')) {
          completePayload = event;
          final content = event['content'];
          final text = (content as List)
              .whereType<Map>()
              .where((block) => block['type'] == 'text')
              .map((block) => (block['text'] ?? '').toString())
              .join();
          if (text.isNotEmpty) onText?.call(text);
          return;
        }
        if (type == 'error') {
          throw const DesktopAxonGatewayFailure(
            'Axon AI could not complete this request. Please try again.',
          );
        }
        if (type == 'message_start') {
          final message = event['message'];
          if (message is Map) {
            messageId = message['id']?.toString();
            model = message['model']?.toString();
            if (message['usage'] is Map) {
              usage = Map<String, dynamic>.from(message['usage'] as Map);
            }
          }
        } else if (type == 'content_block_start') {
          final index = (event['index'] as num?)?.toInt() ?? 0;
          final block = event['content_block'];
          if (block is Map) {
            blocks[index] = Map<String, dynamic>.from(block);
            if (block['type'] == 'tool_use') toolInput[index] = StringBuffer();
          }
        } else if (type == 'content_block_delta') {
          final index = (event['index'] as num?)?.toInt() ?? 0;
          final delta = event['delta'];
          if (delta is Map && delta['type'] == 'text_delta') {
            final text = (delta['text'] ?? '').toString();
            if (text.isNotEmpty) {
              visibleText.write(text);
              onText?.call(visibleText.toString());
              final block = blocks.putIfAbsent(
                index,
                () => <String, dynamic>{'type': 'text', 'text': ''},
              );
              block['text'] = '${block['text'] ?? ''}$text';
            }
          } else if (delta is Map && delta['type'] == 'input_json_delta') {
            toolInput
                .putIfAbsent(index, () => StringBuffer())
                .write((delta['partial_json'] ?? '').toString());
          }
        } else if (type == 'message_delta') {
          final delta = event['delta'];
          if (delta is Map) stopReason = delta['stop_reason']?.toString();
          if (event['usage'] is Map) {
            usage = {
              ...usage,
              ...Map<String, dynamic>.from(event['usage'] as Map),
            };
          }
        }
      }

      if (!(response.headers.contentType?.mimeType ?? '')
          .toLowerCase()
          .contains('text/event-stream')) {
        final bytes = <int>[];
        await for (final chunk in response.timeout(_timeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > _maxResponseBytes) {
            throw const DesktopAxonGatewayFailure(
              'Axon AI returned an unexpectedly large response. Try a shorter question.',
            );
          }
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an invalid response. Please try again.',
          );
        }
        return Map<String, dynamic>.from(decoded);
      }

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        receivedBytes += utf8.encode(line).length + 1;
        if (receivedBytes > _maxResponseBytes) {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an unexpectedly large response. Try a shorter question.',
          );
        }
        if (line.isEmpty) {
          emitEvent();
        } else if (line.startsWith('data:')) {
          if (eventData.isNotEmpty) eventData.write('\n');
          eventData.write(line.substring(5).trimLeft());
        } else if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        }
      }
      emitEvent();
      if (completePayload != null) return completePayload!;

      for (final entry in toolInput.entries) {
        final target = blocks[entry.key];
        if (target == null) continue;
        try {
          target['input'] = entry.value.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(entry.value.toString());
        } on FormatException {
          throw const DesktopAxonGatewayFailure(
            'Axon AI returned an incomplete lookup request. Please try again.',
          );
        }
      }
      final content = blocks.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      if (content.isEmpty || stopReason == null) {
        throw const DesktopAxonGatewayFailure(
          'Axon AI returned an incomplete streamed response. Please try again.',
        );
      }
      return {
        'id': ?messageId,
        'model': ?model,
        'content': content.map((entry) => entry.value).toList(),
        'stop_reason': stopReason,
        'usage': usage,
      };
    } on DesktopAxonGatewayFailure {
      rethrow;
    } on TimeoutException {
      throw const DesktopAxonGatewayFailure(
        'Axon AI took too long to respond. Check the connection and try again.',
      );
    } on SocketException {
      throw const DesktopAxonGatewayFailure(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } on FormatException {
      throw const DesktopAxonGatewayFailure(
        'Axon AI returned an invalid streamed response. Please try again.',
      );
    } on HttpException {
      throw const DesktopAxonGatewayFailure(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } catch (_) {
      throw const DesktopAxonGatewayFailure(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  DesktopAxonGatewayFailure _statusFailure(int status) {
    if (status == 401 || status == 403) {
      return const DesktopAxonGatewayFailure(
        'The saved Axon Gateway key was not accepted. Ask the account owner to check it.',
      );
    }
    if (status == 429) {
      return const DesktopAxonGatewayFailure(
        'Axon AI is busy. Wait a moment and try again.',
      );
    }
    if (status >= 500) {
      return const DesktopAxonGatewayFailure(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    }
    return const DesktopAxonGatewayFailure(
      'Axon AI could not process this request. Please try again.',
    );
  }
}
