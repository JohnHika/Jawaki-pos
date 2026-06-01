import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:levisa_adventures_pos/core/services/storage_service.dart';
import 'package:levisa_adventures_pos/features/ai-billing/presentation/services/ai_billing_service.dart';
import 'package:levisa_adventures_pos/core/di/injection.dart';

class AiChatService {
  AiChatService._internal();
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;

  final List<Map<String, String>> _messages = [];
  final Map<String, dynamic> _storeInfo = {};

  String get _baseUrl {
    final storage = getIt<StorageService>();
    final savedUrl = storage.getServerBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
    final ip = storage.getBackendServerIp();
    final port = storage.getBackendServerPort();
    if (ip != null && ip.isNotEmpty) {
      return 'http://$ip:$port/api/v1';
    }
    return 'https://arche-axon-pos-api.onrender.com/api/v1';
  }

  String get branchId {
    return _storeInfo['branchId'] ?? '';
  }

  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  void setStoreInfo(Map<String, dynamic> info) {
    _storeInfo.clear();
    _storeInfo.addAll(info);
  }

  void clearHistory() {
    _messages.clear();
  }

  void addUserMessage(String content) {
    _messages.add({'role': 'user', 'content': content});
  }

  Future<Map<String, dynamic>> checkSubscriptionStatus() async {
    final billing = getIt<AiBillingService>();
    return await billing.getStatus(branchId);
  }

  Future<bool> canUseAi() async {
    try {
      final billing = getIt<AiBillingService>();
      final result = await billing.getStatus(branchId);
      final status = result['status'] ?? '';
      final daysLeft = result['daysLeft'] ?? 0;
      
      if (status == 'TRIAL') return true;
      if (status == 'ACTIVE' && daysLeft > 0) return true;
      return false;
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Subscription check error: $e');
      return false;
    }
  }

  Future<String> sendMessage({
    required String content,
    String context = 'general',
  }) async {
    addUserMessage(content);

    try {
      // Check subscription before sending
      final canUse = await canUseAi();
      if (!canUse) {
        final error = 'Your AI subscription has expired. Please subscribe to continue using AI features.';
        _messages.add({'role': 'assistant', 'content': error});
        return error;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: {
              'Content-Type': 'application/json',
              'X-Branch-Id': branchId,
            },
            body: jsonEncode({
              'messages': _messages,
              'context': context,
              'branchId': branchId,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['data']['reply'] as String;
        _messages.add({'role': 'assistant', 'content': reply});
        return reply;
      } else if (response.statusCode == 403) {
        final error = 'Your AI subscription is no longer active. Please subscribe to continue using AI features.';
        _messages.add({'role': 'assistant', 'content': error});
        return error;
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
