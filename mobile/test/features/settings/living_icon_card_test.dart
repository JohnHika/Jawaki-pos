import 'package:axon_pos/core/services/app_icon_service.dart';
import 'package:axon_pos/features/settings/presentation/widgets/living_icon_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String active;
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
    channel = const MethodChannel('axon_pos/app_icon');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getIcon') return active;
      if (call.method == 'setIcon') {
        active = call.arguments['key'] as String;
        return true;
      }
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

  testWidgets('starts on and explains automatic icon changes without a picker',
      (tester) async {
    await pump(tester, service());
    expect(find.text('App icon'), findsOneWidget);
    expect(find.textContaining('no current record day'), findsOneWidget);
    expect(find.textContaining('stays on your device'), findsOneWidget);
    expect(find.textContaining('20 hours'), findsOneWidget);
    expect(find.text('AUTOMATIC'), findsOneWidget);
    expect(find.byKey(const ValueKey('living-icon-gallery')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Add to home screen'), findsNothing);
  });

  testWidgets('shows the current automatic milestone without a user picker',
      (tester) async {
    active = 'streak_6';
    await pump(tester, service(streak: 6));

    expect(find.text('6-day streak'), findsOneWidget);
    expect(
      find.text('Your shop has recorded sales for at least six days in a row.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('living-icon-switch')), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });
}
