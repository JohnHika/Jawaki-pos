import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/connectivity_service.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'ai_chat_prefs.dart';

/// Thrown when the backend rejects an AI request with 402 Payment
/// Required — this branch has no active AI subscription.
class AiSubscriptionRequiredException implements Exception {
  const AiSubscriptionRequiredException();
}

/// A single AskUserQuestion question, matching the backend/gateway schema
/// (question/header/options[label,description]/multiSelect).
class AiPendingQuestion {
  final String question;
  final String header;
  final List<AiPendingQuestionOption> options;
  final bool multiSelect;

  AiPendingQuestion({
    required this.question,
    required this.header,
    required this.options,
    required this.multiSelect,
  });

  factory AiPendingQuestion.fromJson(Map<String, dynamic> json) {
    return AiPendingQuestion(
      question: (json['question'] ?? '').toString(),
      header: (json['header'] ?? '').toString(),
      options: ((json['options'] as List?) ?? const [])
          .map((o) => AiPendingQuestionOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      multiSelect: json['multiSelect'] == true,
    );
  }
}

class AiPendingQuestionOption {
  final String label;
  final String description;

  AiPendingQuestionOption({required this.label, required this.description});

  factory AiPendingQuestionOption.fromJson(Map<String, dynamic> json) {
    return AiPendingQuestionOption(
      label: (json['label'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}

/// A paused agent turn awaiting the user — either a multiple-choice
/// question (AskUserQuestion) or a yes/no confirmation before a mutating
/// tool (e.g. raising a stock reorder) is allowed to run. Ephemeral: never
/// persisted to the shared conversation, mirroring the backend which only
/// persists once the turn resolves to a real reply.
class AiPendingTurn {
  final String type; // 'question' | 'confirmation'
  final Map<String, dynamic> toolCall;
  final List<AiPendingQuestion> questions;
  final String? summary;

  AiPendingTurn({
    required this.type,
    required this.toolCall,
    this.questions = const [],
    this.summary,
  });

  factory AiPendingTurn.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString();
    return AiPendingTurn(
      type: type,
      toolCall: (json['tool_call'] as Map?)?.cast<String, dynamic>() ?? const {},
      questions: type == 'question'
          ? ((json['questions'] as List?) ?? const [])
              .map((q) => AiPendingQuestion.fromJson(q as Map<String, dynamic>))
              .toList()
          : const [],
      summary: json['summary'] as String?,
    );
  }
}

/// Result of a send/resume call: either a final text reply, or a paused
/// turn the UI must render interactively before the conversation can
/// continue.
class AiSendResult {
  final String? reply;
  final AiPendingTurn? pending;

  AiSendResult({this.reply, this.pending});
}

class AiChatService {
  AiChatService._internal();
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;

  final List<Map<String, String>> _messages = [];
  final Map<String, dynamic> _storeInfo = {};

  /// The current paused agent turn awaiting the user, if any. Cleared once
  /// resolved (answered/confirmed/declined) or when a new conversation
  /// starts.
  AiPendingTurn? pendingTurn;

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

  // The AI endpoints are now JWT-guarded (shared per-shop history is scoped
  // by the authenticated tenant), so every request must carry the bearer
  // token. This service uses raw http (not the Dio client), so the header
  // is attached explicitly here.
  Map<String, String> _headers({bool json = true}) {
    final token = getIt<AuthService>().accessToken;
    return {
      if (json) 'Content-Type': 'application/json',
      'X-Branch-Id': branchId,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  void setStoreInfo(Map<String, dynamic> info) {
    _storeInfo.clear();
    _storeInfo.addAll(info);
  }

  void clearHistory() {
    _messages.clear();
    pendingTurn = null;
  }

  /// Loads the shop's shared AI conversation from the backend so every
  /// staff member sees the same thread. Called when the chat screen opens.
  /// Silent no-op on failure (offline/new tenant) — the in-memory list
  /// remains whatever it was.
  Future<void> loadSharedHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ai/conversation?branchId=$branchId'),
        headers: _headers(json: false),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final msgs = data['data']?['messages'] as List?;
      if (msgs == null) return;
      pendingTurn = null;
      _messages
        ..clear()
        ..addAll(msgs.map((m) => {
              'role': (m['role'] ?? 'assistant').toString(),
              'content': (m['content'] ?? '').toString(),
            }));
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Load shared history error: $e');
    }
  }

  /// Archives the shop's shared thread on the backend and clears locally,
  /// so "New conversation" starts fresh for everyone.
  Future<void> startNewSharedConversation() async {
    _messages.clear();
    pendingTurn = null;
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/ai/conversation/new'),
            headers: _headers(),
            body: jsonEncode({'branchId': branchId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] New conversation error: $e');
    }
  }

  /// Drops every message from [index] onward — used by "edit & resubmit":
  /// the edited user message and everything after it is removed so the
  /// conversation can continue fresh from that point.
  void truncateFrom(int index) {
    if (index < 0 || index >= _messages.length) return;
    _messages.removeRange(index, _messages.length);
  }

  void addUserMessage(String content) {
    _messages.add({'role': 'user', 'content': content});
  }

  Future<AiSendResult> sendMessage({
    required String content,
    String context = 'general',
  }) async {
    addUserMessage(content);
    pendingTurn = null;

    try {
      final businessContext = _buildBusinessContext();
      final dataContext = await _buildDataContext();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: _headers(),
            body: jsonEncode({
              'messages': _messages,
              'user_question': content,
              'context': context,
              'includeData': dataContext['data_read_failed'] != true,
              'business_context': businessContext,
              'data_context': dataContext,
              'ai_task': 'analyze_and_recommend',
              'response_style': 'actionable_partner',
              'branchId': branchId,
              'web_search': AiChatPrefs.instance.webSearch,
              'tool_access': AiChatPrefs.instance.toolAccess,
            }),
          )
          .timeout(const Duration(seconds: 30));

      return _handleChatResponse(response);
    } on AiSubscriptionRequiredException {
      rethrow;
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Error: $e');
      const error =
          'Could not reach the AI service. Check your connection and try again.';
      _messages.add({'role': 'assistant', 'content': error});
      return AiSendResult(reply: error);
    }
  }

  /// Resumes a paused agent turn ([pendingTurn]) with the user's answer(s)
  /// to an AskUserQuestion, or their approve/decline on a mutating tool
  /// call — the counterpart to the backend's `pending_tool_call` +
  /// `question_answers`/`tool_confirmed` resume contract. Does not add a
  /// new user-visible chat bubble; the question/confirmation UI itself
  /// stands in for that turn.
  Future<AiSendResult> resumePendingTurn({
    Map<String, String>? questionAnswers,
    bool? toolConfirmed,
  }) async {
    final pending = pendingTurn;
    if (pending == null) {
      return AiSendResult(reply: null);
    }
    pendingTurn = null;

    try {
      final businessContext = _buildBusinessContext();
      final dataContext = await _buildDataContext();

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai/chat'),
            headers: _headers(),
            body: jsonEncode({
              'messages': _messages,
              'context': 'general',
              'includeData': dataContext['data_read_failed'] != true,
              'business_context': businessContext,
              'data_context': dataContext,
              'ai_task': 'analyze_and_recommend',
              'response_style': 'actionable_partner',
              'branchId': branchId,
              'web_search': AiChatPrefs.instance.webSearch,
              'tool_access': AiChatPrefs.instance.toolAccess,
              'pending_tool_call': pending.toolCall,
              if (questionAnswers != null) 'question_answers': questionAnswers,
              if (toolConfirmed != null) 'tool_confirmed': toolConfirmed,
            }),
          )
          .timeout(const Duration(seconds: 30));

      return _handleChatResponse(response);
    } catch (e) {
      if (!kReleaseMode) debugPrint('[AiChat] Resume error: $e');
      const error =
          'Could not reach the AI service. Check your connection and try again.';
      _messages.add({'role': 'assistant', 'content': error});
      return AiSendResult(reply: error);
    }
  }

  AiSendResult _handleChatResponse(http.Response response) {
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final payload = data['data'] as Map<String, dynamic>;
      final pendingJson = payload['pending'] as Map<String, dynamic>?;

      if (pendingJson != null) {
        pendingTurn = AiPendingTurn.fromJson(pendingJson);
        return AiSendResult(pending: pendingTurn);
      }

      final reply = payload['reply'] as String;
      _messages.add({'role': 'assistant', 'content': reply});
      return AiSendResult(reply: reply);
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
      return AiSendResult(reply: error);
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
        headers: _headers(json: false),
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
            headers: _headers(),
            body: jsonEncode({
              'messages': const [],
              'user_question':
                  "Give me a short 2-3 sentence brief on today's business performance and one concrete suggestion. "
                  "This will be shown in a narrow mobile card, so if you need to list specific items, use a short "
                  "bullet list (max 3 items, one line each) instead of a markdown table.",
              'context': 'daily_brief',
              'includeData': dataContext['data_read_failed'] != true,
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
    // Whether the device currently has connectivity. This is the ONE signal
    // that legitimately explains missing/stale data — everything else the
    // AI sees is the real, current state of the business.
    final isOffline = getIt<ConnectivityService>().isOffline;

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

      final transactions =
          (dashboard['transactionCount'] as num?)?.toInt() ?? 0;

      return {
        // --- Grounding signals: tell the AI this data is authoritative so
        // it stops speculating about connectivity/sync when it sees zeros.
        // A zero here means the thing genuinely hasn't happened yet today,
        // NOT that data is missing or the POS is offline.
        'data_source': 'local_pos_database',
        'data_is_authoritative': true,
        'is_offline': isOffline,
        'data_freshness': isOffline ? 'last_known' : 'live',
        'has_sales_today': transactions > 0,
        // --- Actual figures ---
        'total_sales': dashboard['totalRevenue'] ?? 0,
        'transactions': transactions,
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
      // Even on failure, still tell the AI whether we're offline and that
      // no data could be read — never leave it to guess.
      return {
        'data_source': 'local_pos_database',
        'data_is_authoritative': true,
        'is_offline': isOffline,
        'data_freshness': isOffline ? 'last_known' : 'live',
        'data_read_failed': true,
      };
    }
  }
}
