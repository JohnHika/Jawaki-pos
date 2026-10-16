import 'package:axon_pos/core/services/app_icon_service.dart';
import 'package:axon_pos/features/settings/presentation/widgets/living_icon_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String active;
  late List<String> calls;
  late MethodChannel channel;

  AppIconService service({int streak = 0}) => AppIconService(
        channel: channel,
        clock: () => DateTime(2026, 10, 16, 10),
        signalsLoader: (_, __) async => AppIconSignals(
          now: DateTime(2026, 10, 16, 10),
          tradingStreakDays: streak,
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    active = 'standard';
    calls = [];
    channel = const MethodChannel('axon_pos/app_icon');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getIcon') return active;
      if (call.method == 'setIcon') {
        active = call.arguments['key'] as String;
        return true;
      }
      if (call.method == 'pinCurrentIcon') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester, AppIconService svc) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: LivingIconCard(service: svc)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final switchFinder = find.byKey(const ValueKey('living-icon-switch'));

  testWidgets('starts off, explains itself and lists every icon', (tester) async {
    await pump(tester, service());
    expect(find.text('Living app icon'), findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    for (final v in AppIconVariant.values) {
      expect(find.text(v.title), findsOneWidget);
    }
    expect(find.textContaining('nothing is sent anywhere'), findsOneWidget);
    expect(find.textContaining('at most once a day'), findsOneWidget);
    expect(find.text('Add to home screen'), findsNothing);
  });

  testWidgets('switching it on waits for the app to be left, never switches now',
      (tester) async {
    await pump(tester, service(streak: 5));
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(active, 'standard', reason: 'switching in the foreground closes the app');
    expect(calls, isNot(contains('setIcon')));
    expect(find.textContaining('updates the next time you leave the app'),
        findsOneWidget);
    expect(find.text('Add to home screen'), findsOneWidget);
  });

  testWidgets('Add to home screen asks the phone to pin the icon', (tester) async {
    await pump(tester, service());
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('living-icon-pin')));
    await tester.pumpAndSettle();

    expect(calls, contains('pinCurrentIcon'));
    expect(find.textContaining('Check the prompt'), findsOneWidget);
  });

  testWidgets('switching it off says the everyday icon returns later', (tester) async {
    await pump(tester, service());
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(find.textContaining('everyday icon comes back'), findsOneWidget);
  });
}
