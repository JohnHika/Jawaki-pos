import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/ai_subscription.dart';
import '../models/store.dart';

class ApiService {
  final http.Client _client = http.Client();
  String? _authToken;

  // ---- Mock data for offline/demo ----
  static final Map<String, dynamic> _mockData = {
    'store_001': {
      'subscription': {
        'id': 'sub_001',
        'store_id': 'store_001',
        'status': 'trial',
        'trial_end_date': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
        'end_date': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
        'auto_renew': false,
      },
      'chat_history': [
        {
          'role': 'assistant',
          'message':
              'Welcome to Jawaki AI! I can help you with sales reports, inventory checks, customer insights, and more. How can I help you today?',
          'timestamp': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        },
        {
          'role': 'user',
          'message': 'What were my top selling items yesterday?',
          'timestamp': DateTime.now()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
        },
        {
          'role': 'assistant',
          'message':
              'Yesterday\'s top sellers:\n1. 🥛 Fresh Milk (48 units)\n2. 🍞 Loaf Bread (35 units)\n3. 🥚 Eggs (30 trays)\n4. 🧈 Cooking Oil - 2L (22 units)\n5. 🍚 Rice - 5kg (18 units)\n\nTotal sales: KES 45,320',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 50))
              .toIso8601String(),
        },
      ],
    },
    'store_002': {
      'subscription': {
        'id': 'sub_002',
        'store_id': 'store_002',
        'status': 'active',
        'start_date': DateTime.now()
            .subtract(const Duration(days: 7))
            .toIso8601String(),
        'end_date':
            DateTime.now().add(const Duration(days: 23)).toIso8601String(),
        'auto_renew': true,
      },
      'chat_history': [],
    },
  };

  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // ---- AI Status ----
  Future<AiSubscription?> checkAiStatus(String storeId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConstants.apiBaseUrl}/ai/subscription/$storeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AiSubscription.fromJson(data);
      }
      return null;
    } catch (e) {
      // Return mock data when backend is unreachable
      return _getMockSubscription(storeId);
    }
  }

  // ---- Initiate Subscription ----
  Future<Map<String, dynamic>?> initiateSubscription(
      String storeId, String mpesaCode) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConstants.apiBaseUrl}/ai/subscribe'),
            headers: _headers,
            body: jsonEncode({
              'store_id': storeId,
              'mpesa_code': mpesaCode,
              'amount': ApiConstants.aiPrice,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'error': 'Payment failed', 'code': response.statusCode};
    } catch (e) {
      // Mock success for demo
      return {
        'payment_id': 'pay_${DateTime.now().millisecondsSinceEpoch}',
        'status': 'pending_verification',
        'message': 'Payment code received. Verify via SMS to activate.',
      };
    }
  }

  // ---- Verify Payment via SMS ----
  Future<Map<String, dynamic>> verifyPayment(
      String paymentId, String mpesaCode, {String? storeId}) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConstants.apiBaseUrl}/ai/verify-payment'),
            headers: _headers,
            body: jsonEncode({
              'payment_id': paymentId,
              'mpesa_code': mpesaCode,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'Verification failed'};
    } catch (e) {
      // Mock success for demo
      return {
        'success': true,
        'subscription': {
          'id': 'sub_${DateTime.now().millisecondsSinceEpoch}',
          'store_id': storeId ?? 'store_001',
          'status': 'active',
          'start_date': DateTime.now().toIso8601String(),
          'end_date':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          'auto_renew': true,
        },
      };
    }
  }

  // ---- AI Chat History ----
  Future<List<Map<String, dynamic>>> getAiChatHistory(String storeId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConstants.apiBaseUrl}/ai/chat/$storeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return _getMockChatHistory(storeId);
    }
  }

  // ---- Send AI Message ----
  Future<Map<String, dynamic>> sendAiMessage(
      String storeId, String message) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConstants.apiBaseUrl}/ai/chat'),
            headers: _headers,
            body: jsonEncode({
              'store_id': storeId,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'error': 'Failed to get AI response'};
    } catch (e) {
      // Generate a mock AI response
      return _generateMockAiResponse(message);
    }
  }

  // ---- Get Store Details ----
  Future<Store?> getStoreDetails(String storeId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConstants.apiBaseUrl}/stores/$storeId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return Store.fromJson(data);
      }
      return null;
    } catch (e) {
      final stores = Store.mockStores();
      return stores.firstWhere(
        (s) => s.id == storeId,
        orElse: () => stores.first,
      );
    }
  }

  // ---- Mock Helpers ----
  AiSubscription? _getMockSubscription(String storeId) {
    final data = _mockData[storeId]?['subscription'] as Map<String, dynamic>?;
    if (data != null) {
      return AiSubscription.fromJson(data);
    }
    return null;
  }

  List<Map<String, dynamic>> _getMockChatHistory(String storeId) {
    final data =
        _mockData[storeId]?['chat_history'] as List<dynamic>? ?? [];
    return data.cast<Map<String, dynamic>>();
  }

  Map<String, dynamic> _generateMockAiResponse(String message) {
    final lowerMsg = message.toLowerCase();
    String response;

    if (lowerMsg.contains('sale') || lowerMsg.contains('revenue')) {
      response =
          '📊 **Sales Overview**\n\nToday: KES 12,450\nThis Week: KES 78,320\nThis Month: KES 342,150\n\nTop category: Dairy & Beverages (32% of sales)';
    } else if (lowerMsg.contains('inventory') || lowerMsg.contains('stock')) {
      response =
          '📦 **Inventory Alert**\n\nItems below reorder level:\n• Fresh Milk — 12 units left\n• Cooking Oil 2L — 8 units left\n• Sugar 1kg — 20 units left\n\nWould you like to generate a purchase order?';
    } else if (lowerMsg.contains('customer') || lowerMsg.contains('loyalty')) {
      response =
          '👥 **Customer Insights**\n\nTotal registered customers: 245\nRepeat customers this month: 89\nTop customer: Mary W. (KES 12,450 spent)\n\nLoyalty points issued today: 1,240';
    } else if (lowerMsg.contains('profit') || lowerMsg.contains('margin')) {
      response =
          '💰 **Profit Analysis**\n\nGross margin today: 28.5%\nAverage markup: 35%\nHighest margin: Electronics (45%)\nLowest margin: Basic Goods (12%)';
    } else if (lowerMsg.contains('help') || lowerMsg.contains('what can')) {
      response =
          '🤖 I can help you with:\n\n• 📊 Sales reports & revenue\n• 📦 Inventory & stock alerts\n• 👥 Customer insights\n• 💰 Profit margins\n• 📅 Daily/weekly summaries\n• 🎯 Business recommendations\n\nJust type your question!';
    } else {
      response =
          'Thanks for your question! I\'ve noted it and will provide relevant insights. For now, here are some quick stats:\n\nToday\'s sales: KES 12,450\nOrders processed: 34\nActive customers: 18\n\nWould you like a detailed report on any specific area?';
    }

    return {
      'role': 'assistant',
      'message': response,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void dispose() {
    _client.close();
  }
}
