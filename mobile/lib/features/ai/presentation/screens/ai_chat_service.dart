import 'dart:convert';

import 'package:axon_pos/core/services/axon_gateway_client.dart';
import 'package:axon_pos/core/database/app_database.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:uuid/uuid.dart';

/// A single AskUserQuestion question, matching the Axon Gateway schema
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
          .map((o) =>
              AiPendingQuestionOption.fromJson(o as Map<String, dynamic>))
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

/// A paused agent turn awaiting the user — a multiple-choice question
/// (AskUserQuestion), a yes/no confirmation before a mutating tool (e.g.
/// raising a stock reorder) is allowed to run, or a proposed plan awaiting
/// approval before a multi-step task proceeds. Ephemeral: never persisted
/// to the shared conversation, mirroring the backend which only persists
/// once the turn resolves to a real reply.
class AiPendingTurn {
  final String type; // 'question' | 'confirmation' | 'plan'
  final Map<String, dynamic> toolCall;
  final List<AiPendingQuestion> questions;
  final String? summary;
  final String? plan;

  AiPendingTurn({
    required this.type,
    required this.toolCall,
    this.questions = const [],
    this.summary,
    this.plan,
  });

  factory AiPendingTurn.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString();
    return AiPendingTurn(
      type: type,
      toolCall:
          (json['tool_call'] as Map?)?.cast<String, dynamic>() ?? const {},
      questions: type == 'question'
          ? ((json['questions'] as List?) ?? const [])
              .map((q) => AiPendingQuestion.fromJson(q as Map<String, dynamic>))
              .toList()
          : const [],
      summary: json['summary'] as String?,
      plan: json['plan'] as String?,
    );
  }
}

/// A single TodoWrite task — mirrors the backend's TodoItemDto exactly so
/// it can be echoed back verbatim on the next turn.
class AiTodoItem {
  final String content;
  final String status; // 'pending' | 'in_progress' | 'completed'
  final String activeForm;

  AiTodoItem(
      {required this.content, required this.status, required this.activeForm});

  factory AiTodoItem.fromJson(Map<String, dynamic> json) {
    return AiTodoItem(
      content: (json['content'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      activeForm: (json['activeForm'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'content': content,
        'status': status,
        'activeForm': activeForm,
      };
}

/// A downloadable file the AI generated (e.g. a PDF/DOCX/CSV report) —
/// carried inline as base64 rather than a URL, since the backend never
/// persists these to storage.
class AiFileAttachment {
  final String base64;
  final String filename;
  final String contentType;

  AiFileAttachment({
    required this.base64,
    required this.filename,
    required this.contentType,
  });

  factory AiFileAttachment.fromJson(Map<String, dynamic> json) {
    return AiFileAttachment(
      base64: (json['base64'] ?? '').toString(),
      filename: (json['filename'] ?? 'report').toString(),
      contentType:
          (json['contentType'] ?? 'application/octet-stream').toString(),
    );
  }
}

/// Result of a send/resume call: either a final text reply, or a paused
/// turn the UI must render interactively before the conversation can
/// continue.
class AiSendResult {
  final String? reply;
  final AiPendingTurn? pending;
  final AiFileAttachment? file;
  final Map<String, dynamic>? chart;

  AiSendResult({this.reply, this.pending, this.file, this.chart});
}

class AiChatService {
  static const _maxMessageChars = 4000;
  static const _maxToolCallsPerTurn = 4;
  static const Uuid _uuid = Uuid();
  static const List<Map<String, dynamic>> _localReadOnlyTools = [
    {
      'name': 'get_today_summary',
      'description': 'Read this device’s saved sales totals for today.',
      'input_schema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_low_stock',
      'description':
          'List local active products at or below their reorder level.',
      'input_schema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_top_products',
      'description':
          'Read the best-selling products in the local sales history for a bounded period.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'days': {
            'type': 'integer',
            'minimum': 1,
            'maximum': 30,
            'description':
                'Number of recent calendar days, from 1 to 30. Defaults to 7.',
          },
        },
        'additionalProperties': false,
      },
    },
    {
      'name': 'search_products',
      'description':
          'Search this device’s local product catalog by name or SKU. Never search for people.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'minLength': 1,
            'maxLength': 80,
          },
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  ];
  AiChatService._internal();
  static final AiChatService _instance = AiChatService._internal();
  factory AiChatService() => _instance;

  /// The only live AI transport is the owner-keyed Axon Gateway client.
  bool get gatewayRequestsEnabled => true;

  Future<bool> isGatewayConfigured() => _gateway.isConfigured();

  final List<Map<String, String>> _messages = [];
  final Map<String, dynamic> _storeInfo = {};
  final AxonGatewayClient _gateway = AxonGatewayClient();

  /// The current paused agent turn awaiting the user, if any. Cleared once
  /// resolved (answered/confirmed/declined) or when a new conversation
  /// starts.
  AiPendingTurn? pendingTurn;

  /// The AI's current live task checklist (TodoWrite), echoed back on each
  /// gateway turn. Cleared on a new conversation.
  List<AiTodoItem> todos = [];

  String get branchId {
    final explicitBranchId = _storeInfo['branchId'] as String?;
    if (explicitBranchId != null && explicitBranchId.isNotEmpty) {
      return explicitBranchId;
    }
    return getIt<StorageService>().getBranchId() ?? '';
  }

  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  /// The business display name used in exports (PDF transcript header).
  String get companyName {
    final user = getIt<StorageService>().getUser() ?? {};
    final tenant = user['tenant'] is Map<String, dynamic>
        ? user['tenant'] as Map<String, dynamic>
        : <String, dynamic>{};
    return (tenant['name'] ?? user['companyName'] ?? 'Counterbase business')
        .toString();
  }

  void setStoreInfo(Map<String, dynamic> info) {
    _storeInfo.clear();
    _storeInfo.addAll(info);
  }

  void clearHistory() {
    _messages.clear();
    pendingTurn = null;
    todos = [];
  }

  /// Conversations stay in memory on this install. Never fetch shared history
  /// from the retired POS service.
  Future<void> loadSharedHistory() async {}

  /// Starts a fresh on-device conversation.
  Future<void> startNewSharedConversation() async {
    clearHistory();
  }

  /// Drops every message from [index] onward in the on-device conversation.
  Future<void> truncateFrom(int index) async {
    if (index < 0 || index >= _messages.length) return;
    _messages.removeRange(index, _messages.length);
  }

  void addUserMessage(String content) {
    final normalized = content.trim();
    _messages.add({
      'id': _uuid.v4(),
      'role': 'user',
      'content': normalized.substring(
        0,
        normalized.length.clamp(0, _maxMessageChars).toInt(),
      ),
    });
  }

  /// Re-runs the last AI response through the configured Axon Gateway.
  Future<AiSendResult> regenerateLast() async {
    if (_messages.isEmpty || _messages.last['role'] != 'assistant') {
      return AiSendResult(reply: null);
    }
    final lastUserIndex = _messages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUserIndex == -1) return AiSendResult(reply: null);

    final question = _messages[lastUserIndex]['content'] ?? '';
    // Truncate back to (and including) that user turn — it gets re-added by
    // sendMessage so local history does not duplicate the question.
    await truncateFrom(lastUserIndex);
    return sendMessage(content: question);
  }

  /// Rewinds the conversation back to (and excluding) the message at
  /// [index]: everything from that point on is dropped locally. If the anchor
  /// was a user message, the caller
  /// typically repopulates the input with its content so the user can
  /// retype/resend from there (mirrors "edit & resubmit" but reachable from
  /// any earlier message, not just the latest).
  Future<void> rewindTo(int index) => truncateFrom(index);

  Future<AiSendResult> sendMessage({
    required String content,
    void Function(String accumulatedText)? onStreamingText,
  }) async {
    final normalizedContent = content.trim();
    if (normalizedContent.isEmpty) return AiSendResult(reply: null);
    addUserMessage(normalizedContent);
    pendingTurn = null;

    try {
      final reply =
          await _runGatewayAgentTurn(onStreamingText: onStreamingText);
      _addAssistantMessage(reply);
      return AiSendResult(reply: reply);
    } on AxonGatewayException catch (error) {
      onStreamingText?.call('');
      _addAssistantMessage(error.message);
      return AiSendResult(reply: error.message);
    } catch (_) {
      onStreamingText?.call('');
      const message =
          'Axon AI could not read the local records. Nothing was changed.';
      _addAssistantMessage(message);
      return AiSendResult(reply: message);
    }
  }

  Future<String> _runGatewayAgentTurn({
    void Function(String accumulatedText)? onStreamingText,
  }) async {
    final history = _messages
        .where((message) =>
            (message['role'] == 'user' || message['role'] == 'assistant') &&
            (message['content'] ?? '').isNotEmpty)
        .toList()
        .reversed
        .take(24)
        .toList()
        .reversed
        .map((message) => <String, dynamic>{
              'role': message['role']!,
              'content': message['content']!,
            })
        .toList();
    const system =
        'You are Axon AI, a concise assistant inside Counterbase POS. '
        'Answer general retail questions normally. You may use the supplied '
        'read-only tools to answer explicit questions about this shop. Tool '
        'results come from this device and are sent to the owner’s Axon Gateway '
        'only when needed to answer the question. Never request or expose customer '
        'personal data. Never claim to change products, stock, prices, payments, '
        'staff, or settings. This assistant cannot execute business actions. '
        'Say when local or unsynchronized records may be incomplete.';

    var localToolCalls = 0;
    for (var round = 0; round < 4; round++) {
      final turn = await _gateway.chatTurnStream(
        system: system,
        messages: history,
        tools: _localReadOnlyTools,
        maxTokens: 1024,
        onText: onStreamingText,
      );
      final rawContent = turn['content'];
      final blocks = rawContent is List
          ? rawContent
              .whereType<Map>()
              .map((block) => Map<String, dynamic>.from(block))
              .toList()
          : <Map<String, dynamic>>[];
      final toolCalls =
          blocks.where((block) => block['type'] == 'tool_use').toList();

      if (turn['stop_reason'] != 'tool_use' || toolCalls.isEmpty) {
        final reply = blocks
            .where((block) => block['type'] == 'text')
            .map((block) => (block['text'] ?? '').toString())
            .where((part) => part.trim().isNotEmpty)
            .join('\n')
            .trim();
        if (reply.isEmpty) {
          throw const AxonGatewayException(
            'Axon AI returned an empty reply. Please try again.',
          );
        }
        return reply;
      }

      // A streamed tool-call turn can include a short preamble. It is not the
      // answer yet; remove it while the device runs the approved read-only
      // lookup and streams the final response on the next round.
      onStreamingText?.call('');

      history.add({'role': 'assistant', 'content': blocks});
      final toolResults = <Map<String, dynamic>>[];
      for (var index = 0; index < toolCalls.length; index++) {
        final call = toolCalls[index];
        final id = (call['id'] ?? '').toString();
        if (id.isEmpty) {
          throw const AxonGatewayException(
            'Axon AI returned an invalid lookup request. Please try again.',
          );
        }
        if (localToolCalls >= _maxToolCallsPerTurn) {
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'is_error': true,
            'content':
                'This lookup was skipped because one turn can use at most $_maxToolCallsPerTurn local lookups. Ask separately. No data was changed.',
          });
          continue;
        }
        localToolCalls++;
        final name = (call['name'] ?? '').toString();
        final input = call['input'] is Map
            ? Map<String, dynamic>.from(call['input'] as Map)
            : <String, dynamic>{};
        try {
          final result = await _runLocalReadOnlyTool(name, input);
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'content': jsonEncode(result),
          });
        } catch (_) {
          toolResults.add({
            'type': 'tool_result',
            'tool_use_id': id,
            'is_error': true,
            'content':
                'This local read-only lookup failed. No data was changed.',
          });
        }
      }
      history.add({'role': 'user', 'content': toolResults});
    }
    throw const AxonGatewayException(
      'Axon AI reached its safe lookup limit. Ask a shorter question.',
    );
  }

  Future<Map<String, dynamic>> _runLocalReadOnlyTool(
    String name,
    Map<String, dynamic> input,
  ) async {
    final database = getIt<AppDatabase>();
    switch (name) {
      case 'get_today_summary':
        final summary = await database.getDashboardSummary(
          branchId: getIt<StorageService>().getBranchId(),
        );
        return {
          'sales': summary['transactionCount'],
          'revenue': summary['totalRevenue'],
          'averageTicket': summary['avgTicket'],
          'itemsSold': summary['itemsSold'],
          'unsyncedSales': summary['unsyncedTransactionCount'],
          'unsyncedRevenue': summary['unsyncedRevenue'],
          'scope': 'local device records for today',
        };
      case 'get_low_stock':
        final rows = await database.getInventoryReport();
        final lowStock = rows.where((row) {
          final stock = (row['stock'] as num?)?.toDouble() ?? 0;
          final threshold = (row['minStock'] as num?)?.toDouble() ?? 0;
          return stock <= threshold;
        }).toList();
        return {
          'items': lowStock
              .take(30)
              .map((row) => {
                    'product': row['name'],
                    'sku': row['sku'],
                    'quantity': row['stock'],
                    'reorderAt': row['minStock'],
                    'unit': row['unit'],
                  })
              .toList(),
          'totalReturned': lowStock.length.clamp(0, 30),
          'truncated': lowStock.length > 30,
          'scope': 'local device inventory for the selected branch',
        };
      case 'get_top_products':
        final days = (input['days'] as num?)?.toInt().clamp(1, 30).toInt() ?? 7;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        // getTopProducts uses an inclusive end bound. Keep a sale stamped at
        // exactly tomorrow's midnight out of this range.
        final endOfToday = today
            .add(const Duration(days: 1))
            .subtract(const Duration(microseconds: 1));
        final rows = await database.getTopProducts(
          today.subtract(Duration(days: days - 1)),
          endOfToday,
          limit: 10,
        );
        return {
          'days': days,
          'items': rows
              .map((row) => {
                    'product': row['productName'],
                    'quantity': row['totalQty'],
                    'revenue': row['totalRevenue'],
                  })
              .toList(),
          'scope': 'completed local sales for the selected branch',
        };
      case 'search_products':
        final query = (input['query'] ?? '').toString().trim();
        if (query.isEmpty || query.length > 80) {
          throw const FormatException('Invalid product search.');
        }
        final products =
            await database.watchProductSuggestions(query, limit: 20).first;
        return {
          'items': products
              .map((product) => {
                    'product': product.name,
                    'sku': product.sku,
                    'price': product.price,
                    'unit': product.unit,
                  })
              .toList(),
          'scope': 'local product catalog',
        };
      default:
        throw const FormatException('Unsupported lookup.');
    }
  }

  /// Resumes a paused agent turn ([pendingTurn]) with the user's answer(s)
  /// to an AskUserQuestion, or their approve/decline on a mutating tool
  /// call. Does not add a new user-visible chat bubble; the question or
  /// confirmation UI itself stands in for that turn.
  Future<AiSendResult> resumePendingTurn({
    Map<String, String>? questionAnswers,
    bool? toolConfirmed,
  }) async {
    if (pendingTurn == null) return AiSendResult(reply: null);
    pendingTurn = null;
    const reply =
        'This Axon AI build cannot resume an action turn. No business action was run.';
    _addAssistantMessage(reply);
    return AiSendResult(reply: reply);
  }

  void _addAssistantMessage(String content) {
    _messages.add({
      'id': _uuid.v4(),
      'role': 'assistant',
      'content': content,
    });
  }

  /// Generates a brief from a small, read-only summary of this device's data.
  /// Customer records, payment references, and staff details are never sent.
  Future<String?> fetchDailyBrief({String? date}) async {
    final auth = getIt<AuthService>();
    if (!auth.isLocalWorkspace || !await _gateway.isConfigured()) return null;

    final branchId = getIt<StorageService>().getBranchId();
    if (branchId == null || branchId.trim().isEmpty) {
      throw const AxonGatewayException(
        'Choose an active shop branch before generating its AI brief.',
      );
    }

    final requestedDay =
        date == null ? DateTime.now() : DateTime.tryParse(date);
    if (requestedDay == null) {
      throw const AxonGatewayException(
        'The selected date could not be read. Refresh and try again.',
      );
    }
    final dayStart =
        DateTime(requestedDay.year, requestedDay.month, requestedDay.day);
    final dayEnd = dayStart
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    final database = getIt<AppDatabase>();
    final results = await Future.wait<dynamic>([
      database.getDailySalesSummary(branchId, dayStart),
      database.getTopProducts(dayStart, dayEnd, limit: 5),
      database.getInventoryAlertCounts(branchId),
    ]);
    final summary = results[0] as Map<String, dynamic>;
    final topProducts = results[1] as List<Map<String, dynamic>>;
    final stockAlerts = results[2] as Map<String, int>;
    final transactionCount =
        (summary['totalTransactions'] as num?)?.toInt() ?? 0;
    final totalSales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
    final business = auth.currentUser?['tenant'];
    final businessName = business is Map
        ? (business['name']?.toString().trim() ?? '')
        : (auth.currentUser?['companyName']?.toString().trim() ?? '');

    final briefContext = <String, dynamic>{
      'business': businessName.isEmpty ? 'Retail shop' : businessName,
      'date': DateFormat('yyyy-MM-dd').format(dayStart),
      'currency': 'KES',
      'sales': totalSales,
      'transactions': transactionCount,
      'averageTicket':
          transactionCount == 0 ? 0 : totalSales / transactionCount,
      'discounts': summary['totalDiscount'],
      'topProducts': topProducts
          .map((product) => {
                'name': product['productName'],
                'quantitySold': product['totalQty'],
                'revenue': product['totalRevenue'],
              })
          .toList(growable: false),
      'lowStockItems': stockAlerts['lowStock'] ?? 0,
      'outOfStockItems': stockAlerts['outOfStock'] ?? 0,
      'dataScope': 'Records saved on this device for the selected branch only',
    };

    return _gateway.chat(
      system:
          'You are Axon AI, the retail assistant in Counterbase. Write a concise, accurate 2–3 sentence business brief for a narrow mobile dashboard card, followed by one practical suggestion. Use only the supplied aggregate figures. Do not invent causes, compare with periods not supplied, include personal data, or use a table. If there were no sales, say so plainly and focus the suggestion on a useful next step.',
      messages: [
        {
          'role': 'user',
          'content':
              'Prepare the daily brief from this selected-branch summary:\n${jsonEncode(briefContext)}',
        },
      ],
      maxTokens: 320,
    );
  }
}
