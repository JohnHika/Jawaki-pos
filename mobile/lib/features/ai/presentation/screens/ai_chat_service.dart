import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/di/injection.dart';

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
      } else {
        final error =
            'Sorry, the AI service is unavailable right now. (${response.statusCode})';
        _messages.add({'role': 'assistant', 'content': error});
        return error;
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Error: $e');
      const error =
          'Could not reach the AI service. Check your connection and try again.';
      _messages.add({'role': 'assistant', 'content': error});
      return error;
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
      final lowStock = await db.getLowStockProducts(threshold: 10);
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
