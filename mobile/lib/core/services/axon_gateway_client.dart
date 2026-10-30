import 'dart:convert';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:http/http.dart' as http;

/// Typed, user-safe failures from the owner-managed Axon AI Gateway.
/// The API key and raw provider response are intentionally never included.
class AxonGatewayException implements Exception {
  const AxonGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The only remote AI client in the downloadable mobile app.
///
/// Requests are sent to the fixed Axon Gateway hostname; callers cannot pass
/// an arbitrary URL. Credentials are read from platform secure storage for
/// each request and are never logged or copied into ordinary preferences.
class AxonGatewayClient {
  static final http.Client _sharedHttpClient = http.Client();
  static final Uri _chatUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/chat',
  );
  static final Uri _visionUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/vision',
  );
  static final Uri _streamChatUri = Uri.https(
    'gateway.archeaxon.com',
    '/v1/pos/chat/stream',
  );

  static const Duration _requestTimeout = Duration(seconds: 45);
  static const int _maxResponseBytes = 2 * 1024 * 1024;
  static const int maxVisionImageBytes = 12 * 1024 * 1024;

  final http.Client _httpClient;

  AxonGatewayClient({http.Client? httpClient})
      : _httpClient = httpClient ?? _sharedHttpClient;

  Future<bool> isConfigured() => getIt<StorageService>().hasAxonGatewayApiKey();

  Future<String> chat({
    required String system,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    int maxTokens = 1024,
  }) async {
    final payload = await chatTurn(
      system: system,
      messages: messages,
      tools: tools,
      maxTokens: maxTokens,
    );

    final stopReason = (payload['stop_reason'] ?? '').toString();
    if (stopReason == 'tool_use') {
      // The standalone client deliberately has no executor for remote code
      // or business mutations. Never pretend a requested tool was completed.
      throw const AxonGatewayException(
        'Axon AI requested an action that this device cannot safely run yet.',
      );
    }

    final content = payload['content'];
    final text = content is List
        ? content
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => (block['text'] ?? '').toString())
            .where((part) => part.trim().isNotEmpty)
            .join('\n')
            .trim()
        : (content ?? '').toString().trim();
    if (text.isEmpty) {
      throw const AxonGatewayException(
        'Axon AI returned an empty reply. Please try again.',
      );
    }
    return text;
  }

  /// Sends one Anthropic-compatible agent turn and returns the validated
  /// structured response so the app can execute only its own bounded tools.
  Future<Map<String, dynamic>> chatTurn({
    required String system,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    int maxTokens = 1024,
  }) =>
      _post(
        _chatUri,
        {
          'system': system,
          'messages': messages,
          'tools': tools,
          'max_tokens': maxTokens.clamp(64, 2048),
          'stream': false,
        },
      );

  /// Streams one Anthropic-compatible agent turn. The callback receives the
  /// accumulated visible text so the UI can replace its in-progress bubble.
  /// Tool-use blocks are collected and returned in the same shape as chatTurn.
  Future<Map<String, dynamic>> chatTurnStream({
    required String system,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    int maxTokens = 1024,
    void Function(String accumulatedText)? onText,
  }) =>
      _streamChat(
        {
          'system': system,
          'messages': messages,
          'tools': tools,
          'max_tokens': maxTokens.clamp(64, 2048),
          'stream': true,
        },
        onText: onText,
      );

  Future<String> vision({
    required String prompt,
    required String imageBase64,
    int maxTokens = 1024,
  }) async {
    if (imageBase64.isEmpty) {
      throw const AxonGatewayException('Choose an image first.');
    }
    if (imageBase64.length > maxVisionImageBytes * 4 ~/ 3 + 8) {
      throw const AxonGatewayException(
        'This image is too large to analyze. Choose a smaller image.',
      );
    }
    final payload = await _post(
      _visionUri,
      {
        'prompt': prompt,
        'image_base64': imageBase64,
        'max_tokens': maxTokens,
      },
    );
    final response = (payload['response'] ?? '').toString().trim();
    if (response.isEmpty) {
      throw const AxonGatewayException(
        'Axon AI could not read this image. Try another image.',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    String? apiKey;
    try {
      apiKey = await getIt<StorageService>().getAxonGatewayApiKey();
    } catch (_) {
      throw const AxonGatewayException(
        'This device’s secure credential store is unavailable. No request was sent.',
      );
    }
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AxonGatewayException(
        'Add the owner-issued Axon Gateway key in Settings before using AI. No prompt or image was sent.',
      );
    }

    try {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(body);
      final response = await _httpClient.send(request).timeout(_requestTimeout);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const AxonGatewayException(
          'Axon AI returned an unexpected redirect. The saved key was not forwarded. Contact the account owner.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > _maxResponseBytes) {
        throw const AxonGatewayException(
          'Axon AI returned an unexpectedly large response. Please try a shorter request.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _statusFailure(response.statusCode);
      }

      final responseBytes = <int>[];
      await for (final chunk in response.stream.timeout(_requestTimeout)) {
        if (responseBytes.length + chunk.length > _maxResponseBytes) {
          throw const AxonGatewayException(
            'Axon AI returned an unexpectedly large response. Please try a shorter request.',
          );
        }
        responseBytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(responseBytes));
      if (decoded is! Map) {
        throw const AxonGatewayException(
          'Axon AI returned an invalid response. Please try again.',
        );
      }
      return decoded.cast<String, dynamic>();
    } on AxonGatewayException {
      rethrow;
    } on http.ClientException {
      throw const AxonGatewayException(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } on FormatException {
      throw const AxonGatewayException(
        'Axon AI returned an invalid response. Please try again.',
      );
    } on Exception {
      throw const AxonGatewayException(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>> _streamChat(
    Map<String, dynamic> body, {
    void Function(String accumulatedText)? onText,
  }) async {
    String? apiKey;
    try {
      apiKey = await getIt<StorageService>().getAxonGatewayApiKey();
    } catch (_) {
      throw const AxonGatewayException(
        'This device’s secure credential store is unavailable. No request was sent.',
      );
    }
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const AxonGatewayException(
        'Add the owner-issued Axon Gateway key in Settings before using AI. No prompt or image was sent.',
      );
    }

    try {
      final request = http.Request('POST', _streamChatUri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream, application/json',
        })
        ..body = jsonEncode(body);
      final response = await _httpClient.send(request).timeout(_requestTimeout);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const AxonGatewayException(
          'Axon AI returned an unexpected redirect. The saved key was not forwarded. Contact the account owner.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > _maxResponseBytes) {
        throw const AxonGatewayException(
          'Axon AI returned an unexpectedly large response. Please try a shorter request.',
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
        final type = (event['type'] ?? '').toString();

        // Some compatible gateways emit the final message as one JSON event.
        if (event['content'] is List && event.containsKey('stop_reason')) {
          completePayload = event;
          final content = event['content'];
          final text = content is List
              ? content
                  .whereType<Map>()
                  .where((block) => block['type'] == 'text')
                  .map((block) => (block['text'] ?? '').toString())
                  .join()
              : '';
          if (text.isNotEmpty) onText?.call(text);
          return;
        }

        if (type == 'error' || currentEventName == 'error') {
          throw const AxonGatewayException(
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
            if (block['type'] == 'tool_use') {
              toolInput[index] = StringBuffer();
            }
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
            toolInput.putIfAbsent(index, () => StringBuffer()).write(
                  (delta['partial_json'] ?? '').toString(),
                );
          }
        } else if (type == 'message_delta') {
          final delta = event['delta'];
          if (delta is Map) stopReason = delta['stop_reason']?.toString();
          if (event['usage'] is Map) {
            usage = {
              ...usage,
              ...Map<String, dynamic>.from(event['usage'] as Map)
            };
          }
        }
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().contains('text/event-stream')) {
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(_requestTimeout)) {
          receivedBytes += chunk.length;
          if (receivedBytes > _maxResponseBytes) {
            throw const AxonGatewayException(
              'Axon AI returned an unexpectedly large response. Please try a shorter request.',
            );
          }
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) {
          throw const AxonGatewayException(
            'Axon AI returned an invalid response. Please try again.',
          );
        }
        return Map<String, dynamic>.from(decoded);
      }

      await for (final line in response.stream
          .timeout(_requestTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        receivedBytes += utf8.encode(line).length + 1;
        if (receivedBytes > _maxResponseBytes) {
          throw const AxonGatewayException(
            'Axon AI returned an unexpectedly large response. Please try a shorter request.',
          );
        }
        if (line.isEmpty) {
          emitEvent();
        } else if (line.startsWith('data:')) {
          if (eventData.isNotEmpty) eventData.write('\n');
          eventData.write(line.substring(5).trimLeft());
        } else if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith(':')) {
          continue;
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
          throw const AxonGatewayException(
            'Axon AI returned an incomplete lookup request. Please try again.',
          );
        }
      }
      final content = blocks.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      if (content.isEmpty || stopReason == null) {
        throw const AxonGatewayException(
          'Axon AI returned an incomplete streamed response. Please try again.',
        );
      }
      return {
        if (messageId != null) 'id': messageId,
        if (model != null) 'model': model,
        'content': content.map((entry) => entry.value).toList(),
        'stop_reason': stopReason,
        'usage': usage,
      };
    } on AxonGatewayException {
      rethrow;
    } on http.ClientException {
      throw const AxonGatewayException(
        'Could not reach Axon AI. Check the connection and try again.',
      );
    } on FormatException {
      throw const AxonGatewayException(
        'Axon AI returned an invalid streamed response. Please try again.',
      );
    } on Exception {
      throw const AxonGatewayException(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    }
  }

  AxonGatewayException _statusFailure(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return const AxonGatewayException(
        'The saved Axon Gateway key was not accepted. Ask the account owner to check it.',
      );
    }
    if (statusCode == 429) {
      return const AxonGatewayException(
        'Axon AI is busy. Wait a moment and try again.',
      );
    }
    if (statusCode >= 500) {
      return const AxonGatewayException(
        'Axon AI is temporarily unavailable. Please try again.',
      );
    }
    return const AxonGatewayException(
      'Axon AI could not process this request. Please try again.',
    );
  }
}
