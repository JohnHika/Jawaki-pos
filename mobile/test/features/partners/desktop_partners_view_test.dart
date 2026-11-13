import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/desktop/desktop_theme.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/app_theme.dart';
import 'package:axon_pos/features/partners/presentation/desktop/desktop_partners_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/shot.dart';

DateTime _ago({int hours = 0, int days = 0}) =>
    DateTime.now().subtract(Duration(hours: hours, days: days));

Map<String, dynamic> _partner(
  String id,
  String name, {
  String status = 'ACCEPTED',
  String direction = 'outgoing',
  String? note,
  String? last,
  bool lastFromMe = false,
  DateTime? lastAt,
  int unread = 0,
}) =>
    {
      'id': id,
      'status': status,
      'direction': direction,
      'message': note,
      'createdAt': _ago(days: 40).toUtc().toIso8601String(),
      'unreadCount': unread,
      'partner': {
        'tenantId': 't-$id',
        'name': name,
        'slug': name.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
      },
      if (last != null)
        'lastMessage': {
          'body': last,
          'fromMe': lastFromMe,
          'createdAt': (lastAt ?? _ago(hours: 1)).toUtc().toIso8601String(),
        },
    };

Map<String, dynamic> _message(
  String id,
  String body,
  DateTime at, {
  bool fromMe = false,
  String sender = 'Peter Kamau',
}) =>
    {
      'id': id,
      'body': body,
      'createdAt': at.toUtc().toIso8601String(),
      'fromMe': fromMe,
      'senderName': fromMe ? 'You' : sender,
    };

class _FakeApi extends ApiClient {
  _FakeApi({required this.partners, required this.messages}) : super(Dio());

  List<Map<String, dynamic>> partners;
  final Map<String, List<Map<String, dynamic>>> messages;
  bool failList = false;
  final sent = <(String, String)>[];
  final accepted = <String>[];
  final declined = <String>[];
  final removed = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getTradePartners() async {
    if (failList) {
      throw DioException(
        requestOptions: RequestOptions(path: '/partners'),
        type: DioExceptionType.connectionError,
      );
    }
    return partners;
  }

  @override
  Future<List<Map<String, dynamic>>> getPartnerMessages(
    String id, {
    String? after,
    int limit = 50,
  }) async =>
      after == null ? [...?messages[id]] : const [];

  @override
  Future<Map<String, dynamic>> sendPartnerMessage(String id, String body) async {
    sent.add((id, body));
    final m = _message('sent-${sent.length}', body, DateTime.now(), fromMe: true);
    (messages[id] ??= []).add(m);
    return m;
  }

  @override
  Future<void> acceptTradePartner(String id) async {
    accepted.add(id);
    partners = [
      for (final p in partners)
        if (p['id'] == id) {...p, 'status': 'ACCEPTED'} else p,
    ];
  }

  @override
  Future<void> declineTradePartner(String id) async {
    declined.add(id);
    partners = [
      for (final p in partners)
        if (p['id'] != id) p,
    ];
  }

  @override
  Future<void> removeTradePartner(String id) async {
    removed.add(id);
    partners = [
      for (final p in partners)
        if (p['id'] != id) p,
    ];
  }
}

_FakeApi _sampleApi() => _FakeApi(
      partners: [
        _partner('p1', 'Kamau Wholesalers',
            last: 'We can deliver the 50 bags of sugar on Thursday morning',
            lastAt: _ago(hours: 1),
            unread: 3),
        _partner('p2', 'Mama Njeri Fresh Produce',
            last: 'Thank you, payment received',
            lastFromMe: false,
            lastAt: _ago(hours: 30)),
        _partner('p3', 'Brookside Dairy Distributors Kenya Limited, Nairobi depot',
            last: 'Okay, send the order list',
            lastFromMe: true,
            lastAt: _ago(days: 3)),
        _partner('p4', 'Unga Millers Depot'),
        _partner('p5', 'Wanjiku Cereals Ltd',
            status: 'PENDING',
            direction: 'incoming',
            note: 'Hi, we supply maize flour and rice to shops in Kiambu. We would like to supply you too.'),
        _partner('p6', 'Nyeri Gas Supplies',
            status: 'PENDING', direction: 'outgoing'),
      ],
      messages: {
        'p1': [
          _message('m1', 'Good morning. Do you still have Pembe maize flour 2kg?', _ago(days: 1, hours: 5), fromMe: true),
          _message('m2', 'Yes, we have 200 bags. KES 118 each for 20 bags or more.', _ago(days: 1, hours: 4)),
          _message('m3', 'Please hold 40 bags for me. I will pay by M-Pesa this afternoon.', _ago(days: 1, hours: 3), fromMe: true),
          _message('m4', 'Done. Send the till number when you pay.', _ago(days: 1, hours: 3)),
          _message('m5', 'Paid KES 4,720, confirmation QJ7K2M91XA.', _ago(hours: 5), fromMe: true),
          _message('m6', 'Received, asante. We can deliver the 50 bags of sugar on Thursday morning too.', _ago(hours: 1)),
          _message('m7', 'Please confirm if that works for you, the lorry leaves at 7.', _ago(hours: 1)),
        ],
        'p2': [
          _message('n1', 'Thank you, payment received', _ago(hours: 30), sender: 'Njeri'),
        ],
      },
    );

const _sizes = {
  '1366': Size(1134, 700),
  '1093': Size(1037, 498),
  '1920': Size(1688, 1012),
};

Future<_FakeApi> _setUp({_FakeApi? api}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  await storage.initialize();
  await storage.saveTenantSlug('mwangi-general-store');
  final fake = api ?? _sampleApi();
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
  if (getIt.isRegistered<StorageService>()) getIt.unregister<StorageService>();
  getIt.registerSingleton<ApiClient>(fake);
  getIt.registerSingleton<StorageService>(storage);
  addTearDown(() {
    if (getIt.isRegistered<ApiClient>()) getIt.unregister<ApiClient>();
    if (getIt.isRegistered<StorageService>()) {
      getIt.unregister<StorageService>();
    }
    DesktopLayout.debugIsDesktopPlatform = null;
  });
  DesktopLayout.debugIsDesktopPlatform = true;
  return fake;
}

Widget _app({
  String? initialId,
  bool dark = false,
  GlobalKey? boundary,
}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final page = DesktopScope(
    sidebarCollapsed: false,
    child: DesktopPartnersPage(initialPartnerId: initialId),
  );
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: DesktopTheme.of(base),
      home: boundary == null ? page : ShotFrame(boundaryKey: boundary, child: page),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadShotFonts);

  for (final dark in [false, true]) {
    for (final entry in _sizes.entries) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('three panes $theme ${entry.key}', (tester) async {
        await _setUp();
        useWindow(tester, entry.value);
        final key = GlobalKey();
        await tester.pumpWidget(_app(initialId: 'p1', dark: dark, boundary: key));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await saveShot(tester, key, 'build/shots/partners-open-$theme-${entry.key}.png');
      });
    }
  }

  testWidgets('no partner picked yet teaches the middle pane', (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(boundary: key));
    await _settle(tester);
    expect(find.text('Pick a partner to message'), findsOneWidget);
    expect(find.text('Requests for you  1'), findsOneWidget);
    expect(find.text('Waiting for a reply  1'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/partners-none-light-1366.png');
  });

  testWidgets('no partners at all says what the page is for', (tester) async {
    await _setUp(api: _FakeApi(partners: [], messages: {}));
    useWindow(tester, _sizes['1093']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(dark: true, boundary: key));
    await _settle(tester);
    expect(find.text('Connect with the businesses you trade with'), findsOneWidget);
    expect(find.text('Connect with a business'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/partners-empty-dark-1093.png');
  });

  testWidgets('a failed first load says so and offers Try again', (tester) async {
    await _setUp(api: _sampleApi()..failList = true);
    useWindow(tester, _sizes['1366']!);
    final key = GlobalKey();
    await tester.pumpWidget(_app(boundary: key));
    await _settle(tester);
    expect(find.text("Couldn't load your partners"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await saveShot(tester, key, 'build/shots/partners-error-light-1366.png');
  });

  testWidgets('picking a partner swaps the conversation without navigating',
      (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(initialId: 'p1'));
    await _settle(tester);
    expect(find.textContaining('the lorry leaves at 7'), findsOneWidget);

    await tester.tap(find.text('Mama Njeri Fresh Produce'));
    await _settle(tester);
    expect(find.textContaining('the lorry leaves at 7'), findsNothing);
    expect(find.text('Thank you, payment received'), findsWidgets);
  });

  testWidgets('arrow keys move through the partner list', (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(initialId: 'p1'));
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    // Newest conversation first: Kamau, Mama Njeri, Brookside, Unga Millers.
    expect(find.text('Thank you, payment received'), findsWidgets);
  });

  testWidgets('Enter sends the message, Shift+Enter does not', (tester) async {
    final api = await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(initialId: 'p1'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).last, 'Thursday works, thanks');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(api.sent, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(api.sent, [('p1', 'Thursday works, thanks')]);
    expect(find.text('Thursday works, thanks'), findsOneWidget);
  });

  testWidgets('a request can be accepted or declined in the list',
      (tester) async {
    final api = await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await tester.tap(find.text('Accept'));
    await _settle(tester);
    expect(api.accepted, ['p5']);
    expect(find.text('Requests for you  1'), findsNothing);
  });

  testWidgets('search narrows the list and says when nothing matches',
      (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'unga');
    await _settle(tester);
    expect(find.text('Unga Millers Depot'), findsOneWidget);
    expect(find.text('Kamau Wholesalers'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await _settle(tester);
    expect(find.text('No partner called "zzz"'), findsOneWidget);
  });

  testWidgets('partner details open on the right and removal asks first',
      (tester) async {
    final api = await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app(initialId: 'p1'));
    await _settle(tester);
    expect(find.text('Remove partner'), findsOneWidget);

    await tester.tap(find.text('Remove partner'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Kamau Wholesalers?'), findsOneWidget);
    await tester.tap(find.text('Keep partner'));
    await tester.pumpAndSettle();
    expect(api.removed, isEmpty);

    await tester.tap(find.text('Remove partner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await _settle(tester);
    expect(api.removed, ['p1']);
    expect(find.text('Pick a partner to message'), findsOneWidget);
  });

  testWidgets('below 1100px the details float over the conversation',
      (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1093']!);
    await tester.pumpWidget(_app(initialId: 'p1'));
    await _settle(tester);
    // Closed by default so the conversation keeps the room.
    expect(find.text('Remove partner'), findsNothing);
    await tester.tap(find.byTooltip('Partner details'));
    await _settle(tester);
    expect(find.text('Remove partner'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Remove partner'), findsNothing);
  });

  testWidgets('Connect opens a dialog, not a bottom sheet', (tester) async {
    await _setUp();
    useWindow(tester, _sizes['1366']!);
    await tester.pumpWidget(_app());
    await _settle(tester);
    await tester.tap(find.text('Connect').first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Connect with a business'), findsOneWidget);
  });
}
