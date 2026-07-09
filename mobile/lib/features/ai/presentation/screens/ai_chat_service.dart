import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/di/injection.dart';

/// Thrown when the backend rejects an AI request with 402 Payment
/// Required — this branch has no active AI subscription.
class AiSubscriptionRequiredException implements Exception {
  const AiSubscriptionRequiredException();
}

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
    final explicitBranchId = _storeInfo['branchId'] as String?;
    if (explicitBranchId != null && explicitBranchId.isNotEmpty) {
      return explicitBranchId;
    }
    return getIt<StorageService>().getBranchId() ?? '';
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

  Future<String> sendMessage({
    required String content,
    String context = 'general',
  }) async {
    addUserMessage(content);

    try {
      final businessContext = _buildBusinessContext();
      final dataContext = await _buildDataContext();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: {
              'Content-Type': 'application/json',
              'X-Branch-Id': branchId,
            },
            body: jsonEncode({
              'messages': _messages,
              'user_question': content,
              'context': context,
              'includeData': dataContext.isNotEmpty,
              'business_context': businessContext,
              'data_context': dataContext,
              'ai_task': 'analyze_and_recommend',
              'response_style': 'actionable_partner',
              'branchId': branchId,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['data']['reply'] as String;
        _messages.add({'role': 'assistant', 'content': reply});
        return reply;
      } else if (response.statusCode == 402) {
        // Remove the pending user message — this turn never produced a
        // reply, and re-sending after subscribing shouldn't leave a
        // duplicate in history.
        if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
          _messages.removeLast();
        }
        throw const AiSubscriptionRequiredException();
      } else {
        final error =
            'Sorry, the AI service is unavailable right now. (${response.statusCode})';
        _messages.add({'role': 'assistant', 'content': error});
        return error;
      }
    } on AiSubscriptionRequiredException {
      rethrow;
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Error: $e');
      const error =
          'Could not reach the AI service. Check your connection and try again.';
      _messages.add({'role': 'assistant', 'content': error});
      return error;
    }
  }

  /// Fetches a short proactive business brief for the dashboard's "AI
  /// Brief" card — distinct from [sendMessage]: this never touches
  /// [_messages] (the real chat history), since it's a background,
  /// dashboard-driven read rather than something the user asked in chat.
  ///
  /// Tries the pre-generated nightly brief first (near-instant, produced by
  /// the backend cron) and only falls back to a live `/ai/chat` call when
  /// none exists yet for today (e.g. a brand new tenant, or the cron
  /// hasn't run yet this morning).
  Future<String?> fetchDailyBrief() async {
    final pregenerated = await _fetchPregeneratedBrief();
    if (pregenerated != null) return pregenerated;
    return _fetchLiveBrief();
  }

  Future<String?> _fetchPregeneratedBrief() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ai/daily-brief?branchId=$branchId'),
        headers: {'X-Branch-Id': branchId},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['data']?['content'] as String?;
        if (content != null && content.trim().isNotEmpty) return content;
      }
      return null;
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Pregenerated brief error: $e');
      return null;
    }
  }

  Future<String?> _fetchLiveBrief() async {
    try {
      final businessContext = _buildBusinessContext();
      final dataContext = await _buildDataContext();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: {
              'Content-Type': 'application/json',
              'X-Branch-Id': branchId,
            },
            body: jsonEncode({
              'messages': const [],
              'user_question':
                  "Give me a short 2-3 sentence brief on today's business performance and one concrete suggestion. "
                  "This will be shown in a narrow mobile card, so if you need to list specific items, use a short "
                  "bullet list (max 3 items, one line each) instead of a markdown table.",
              'context': 'daily_brief',
              'includeData': dataContext.isNotEmpty,
              'business_context': businessContext,
              'data_context': dataContext,
              'ai_task': 'analyze_and_recommend',
              'response_style': 'concise',
              'branchId': branchId,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return data['data']['reply'] as String?;
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Live brief error: $e');
      return null;
    }
  }

  Map<String, dynamic> _buildBusinessContext() {
    final storage = getIt<StorageService>();
    final user = storage.getUser() ?? {};
    final tenant = user['tenant'] is Map<String, dynamic>
        ? user['tenant'] as Map<String, dynamic>
        : <String, dynamic>{};
    final branches =
        user['branches'] is List ? user['branches'] as List : const [];
    final primaryBranch =
        branches.whereType<Map>().cast<Map<String, dynamic>?>().firstWhere(
              (branch) => branch?['id'] == branchId,
              orElse: () => branches
                  .whereType<Map>()
                  .cast<Map<String, dynamic>?>()
                  .firstWhere(
                    (branch) => branch?['isPrimary'] == true,
                    orElse: () => null,
                  ),
            );

    return {
      'business_type': 'retail',
      'company': tenant['name'] ?? user['companyName'] ?? 'Axon POS business',
      'tenant_slug': storage.getTenantSlug() ?? user['tenantSlug'] ?? '',
      'branch': _storeInfo['branchName'] ??
          user['branchName'] ??
          primaryBranch?['name'] ??
          branchId,
      'role': user['role'] ?? '',
      'user_first_name': user['firstName'] ?? '',
      'time_range': 'today',
    };
  }

  Future<Map<String, dynamic>> _buildDataContext() async {
    try {
      final db = getIt<AppDatabase>();
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final dashboard = await db.getDashboardSummary();
      final topProducts =
          await db.getTopProducts(startOfDay, endOfDay, limit: 5);
      final lowStock = await db.getLowStockProducts();
      final branchLowStock = branchId.isEmpty
          ? lowStock
          : lowStock.where((item) {
              final itemBranchId = item['branchId'] as String? ?? '';
              return itemBranchId.isEmpty || itemBranchId == branchId;
            }).toList();

      return {
        'total_sales': dashboard['totalRevenue'] ?? 0,
        'transactions': dashboard['transactionCount'] ?? 0,
        'average_ticket': dashboard['avgTicket'] ?? 0,
        'items_sold': dashboard['itemsSold'] ?? 0,
        'top_products': topProducts
            .map((item) => {
                  'name':
                      item['productName'] ?? item['name'] ?? 'Unnamed product',
                  'quantity_sold': item['totalQty'] ?? 0,
                  'revenue': item['totalRevenue'] ?? 0,
                })
            .toList(),
        'low_stock_items': branchLowStock
            .take(8)
            .map((item) => {
                  'name': item['name'] ?? 'Unnamed product',
                  'sku': item['sku'] ?? '',
                  'category': item['categoryName'] ?? '',
                  'price': item['price'] ?? 0,
                  'remaining_stock': item['quantity'] ?? 0,
                })
            .toList(),
      };
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Data context error: $e');
      return {};
    }
  }
}
