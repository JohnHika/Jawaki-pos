import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/di/injection.dart';
import '../../../../core/services/storage_service.dart';

class AiChatService {
  AiChatService._internal();
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;

  final List<Map<String, String>> _messages = [];

  String get _baseUrl {
    final storage = getIt<StorageService>();
    final ip = storage.getBackendServerIp();
    final port = storage.getBackendServerPort();
    if (ip != null && ip.isNotEmpty) {
      return 'http://$ip:$port/api/v1';
    }
    return 'http://192.168.100.47:3000/api/v1';
  }

  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  void clearHistory() {
    _messages.clear();
  }

  void addUserMessage(String content) {
    _messages.add({'role': 'user', 'content': content});
  }

  Future<String> sendMessage({
    required String content,
    String context = 'general',
    String? storeId,
  }) async {
    addUserMessage(content);

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': _messages,
              'context': context,
              'storeId': storeId,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['data']['reply'] as String;
        _messages.add({'role': 'assistant', 'content': reply});
        return reply;
      } else {
        final error = 'Sorry, the AI service is unavailable right now. (${response.statusCode})';
        _messages.add({'role': 'assistant', 'content': error});
        return error;
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Error: $e');
      final error = 'Could not reach the AI service. Check your connection and try again.';
      _messages.add({'role': 'assistant', 'content': error});
      return error;
    }
  }
}
