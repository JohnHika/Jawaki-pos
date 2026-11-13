import 'dart:async';
import 'dart:convert';

import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/providers/tenant_provider.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/ai/presentation/screens/ai_chat_screen.dart';
import 'package:axon_pos/features/ai/presentation/screens/ai_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/shot.dart';

class _GatewayStorage extends StorageService {
  @override
  Future<String?> getAxonGatewayApiKey() async => 'test-owner-key';

  @override
  Future<bool> hasAxonGatewayApiKey() async => true;

  @override
  String? getBranchId() => 'branch-1';
}

class _ControlledHttpClient extends http.BaseClient {
  final StreamController<_ControlledResponse> _requests =
      StreamController<_ControlledResponse>.broadcast(sync: true);
  final List<_ControlledResponse> _responses = [];
  bool abortWithError = true;
  int closeCalls = 0;

  Future<_ControlledResponse> get nextRequest => _requests.stream.first;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = _ControlledResponse(
      request: request,
      abortWithError: abortWithError,
    );
    _responses.add(response);
    _requests.add(response);
    return http.StreamedResponse(
      response.body.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
      request: request,
    );
  }

  @override
  void close() {
    closeCalls++;
  }

  Future<void> dispose() async {
    for (final response in _responses) {
      await response.dispose();
    }
    await _requests.close();
  }
}

class _ControlledResponse {
  _ControlledResponse({
    required this.request,
    required this.abortWithError,
  }) {
    final trigger = request is http.AbortableRequest
        ? (request as http.AbortableRequest).abortTrigger
        : null;
    trigger?.then((_) {
      abortTriggered = true;
      if (abortWithError && !body.isClosed) {
        body.addError(http.ClientException('Request aborted', request.url));
        unawaited(body.close());
      }
    });
  }

  final http.BaseRequest request;
  final bool abortWithError;
  final StreamController<List<int>> body =
      StreamController<List<int>>(sync: true);
  bool abortTriggered = false;

  void complete(String reply) {
    if (body.isClosed) return;
    final payload = jsonEncode({
      'content': [
        {'type': 'text', 'text': reply},
      ],
      'stop_reason': 'end_turn',
    });
    body.add(utf8.encode('data: $payload\n\n'));
    unawaited(body.close());
  }

  Future<void> dispose() async {
    if (!body.isClosed) await body.close();
  }
}

late _ControlledHttpClient _client;
late AiChatService _service;

Widget _desktopScreen() => ProviderScope(
      overrides: [
        tenantIdentityProvider.overrideWithValue(TenantIdentity.empty),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: DesktopTheme.of(AppTheme.lightTheme),
        home: const DesktopScope(
          sidebarCollapsed: false,
          child: AiChatScreen(),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadShotFonts();
    _client = _ControlledHttpClient();
    if (getIt.isRegistered<StorageService>()) {
      getIt.unregister<StorageService>();
    }
    getIt.registerSingleton<StorageService>(_GatewayStorage());

    // Construct the chat service inside this zone so its shared HTTP client
    // uses the controlled stream client for the duration of these tests.
    await http.runWithClient(() async {
      _service = AiChatService();
    }, () => _client);
  });

  setUp(() {
    _service.clearHistory();
    _client.abortWithError = true;
  });

  tearDown(() => _service.clearHistory());

  tearDownAll(() async {
    if (getIt.isRegistered<StorageService>()) {
      getIt.unregister<StorageService>();
    }
    await _client.dispose();
  });

  test('a new conversation discards a late streamed reply', () async {
    _client.abortWithError = false;
    final requestStarted = _client.nextRequest;
    final send = _service.sendMessage(content: 'Question from the old thread');
    final response = await requestStarted;

    await _service.startNewSharedConversation();
    response.complete('Reply from the old thread');
    final result = await send;

    expect(_service.messages, isEmpty,
        reason: 'the previous thread must not repopulate the new one');
    expect(result.reply, isNull,
        reason: 'a cancelled turn must not return a stale reply');
    expect(response.abortTriggered, isTrue,
        reason: 'the stream request should be aborted, not the shared client');
    expect(_client.closeCalls, 0);
  });

  testWidgets('desktop Stop aborts generation without adding an error',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    await tester.pumpWidget(_desktopScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final requestStarted = _client.nextRequest;
    await tester.enterText(
        find.byType(TextField), 'How did the shop do today?');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final response = await requestStarted;
    await tester.pump();

    try {
      expect(find.byTooltip('Stop generation'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop generation'));
      await tester.pump();

      for (var i = 0; i < 5 && !response.abortTriggered; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump(const Duration(milliseconds: 50));

      expect(response.abortTriggered, isTrue);
      expect(_service.messages.where((m) => m['role'] == 'assistant'), isEmpty);
      expect(
        find.text('Axon AI is temporarily unavailable. Please try again.'),
        findsNothing,
      );
      expect(_client.closeCalls, 0,
          reason: 'cancellation must not close the shared HTTP client');
    } finally {
      response.complete('test cleanup');
      await tester.pump(const Duration(milliseconds: 20));
    }
  });

  testWidgets('the desktop new-conversation action cancels pending generation',
      (tester) async {
    useWindow(tester, const Size(1366, 768));
    await tester.pumpWidget(_desktopScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final requestStarted = _client.nextRequest;
    await tester.enterText(find.byType(TextField), 'Old conversation question');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final response = await requestStarted;
    await tester.pump();

    try {
      expect(find.text('New conversation'), findsOneWidget);
      await tester.tap(find.text('New conversation'));
      await tester.pump();
      for (var i = 0; i < 5 && !response.abortTriggered; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(response.abortTriggered, isTrue);
      expect(_service.messages, isEmpty);
      expect(_client.closeCalls, 0);
    } finally {
      response.complete('test cleanup');
      await tester.pump(const Duration(milliseconds: 20));
    }
  });
}
