import 'package:axon_pos/core/services/app_icon_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppIconSignals _s({
  int streak = 0,
  int outOfStock = 0,
  bool record = false,
}) =>
    AppIconSignals(
      now: DateTime(2026, 10, 16, 10),
      tradingStreakDays: streak,
      outOfStockCount: outOfStock,
      isRecordDay: record,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chooseAppIcon', () {
    test('an ordinary day wears the everyday icon', () {
      expect(chooseAppIcon(_s()), AppIconVariant.standard);
    });

    test('a record day beats everything else', () {
      expect(
        chooseAppIcon(_s(record: true, streak: 9, outOfStock: 4)),
        AppIconVariant.gold,
      );
    });

    test('three trading days in a row is a streak; two is not', () {
      expect(chooseAppIcon(_s(streak: 3)), AppIconVariant.streak);
      expect(chooseAppIcon(_s(streak: 2)), AppIconVariant.standard);
    });

    test('products out of stock raise the alert, below a streak', () {
      expect(chooseAppIcon(_s(outOfStock: 1)), AppIconVariant.alert);
      expect(chooseAppIcon(_s(outOfStock: 1, streak: 5)), AppIconVariant.streak);
    });

    test('nothing flips with the time of day', () {
      for (final hour in [0, 9, 18, 23]) {
        final s = AppIconSignals(now: DateTime(2026, 10, 16, hour));
        expect(chooseAppIcon(s), AppIconVariant.standard);
      }
    });
  });

  group('signalsFromDailyTotals', () {
    final now = DateTime(2026, 10, 16, 9);

    AppIconSignals build(Map<String, int> counts, {Map<String, double>? totals}) =>
        signalsFromDailyTotals(
          now: now,
          dailyTotals: totals ?? {for (final e in counts.entries) e.key: e.value * 100.0},
          dailyCounts: counts,
          outOfStockCount: 0,
        );

    test('counts consecutive days back from today', () {
      final s = build({'2026-10-16': 2, '2026-10-15': 1, '2026-10-14': 4, '2026-10-12': 3});
      expect(s.tradingStreakDays, 3); // the 13th has no sales, so it stops
    });

    test('the streak survives the morning before the first sale', () {
      final s = build({'2026-10-15': 1, '2026-10-14': 1, '2026-10-13': 1});
      expect(s.tradingStreakDays, 3);
    });

    test('a gap breaks the streak', () {
      final s = build({'2026-10-16': 1, '2026-10-14': 1, '2026-10-13': 1});
      expect(s.tradingStreakDays, 1);
    });

    test('a record day needs real sales and history, and to beat every earlier day', () {
      final base = {'2026-10-15': 5, '2026-10-14': 5, '2026-10-13': 5};
      final totals = {'2026-10-15': 400.0, '2026-10-14': 700.0, '2026-10-13': 500.0};

      final beaten = build({...base, '2026-10-16': 4}, totals: {...totals, '2026-10-16': 701});
      expect(beaten.isRecordDay, isTrue);

      final tied = build({...base, '2026-10-16': 4}, totals: {...totals, '2026-10-16': 700});
      expect(tied.isRecordDay, isFalse);

      final fewSales = build({...base, '2026-10-16': 2}, totals: {...totals, '2026-10-16': 900});
      expect(fewSales.isRecordDay, isFalse);

      final newShop = build(
        {'2026-10-15': 5, '2026-10-16': 4},
        totals: {'2026-10-15': 100.0, '2026-10-16': 900.0},
      );
      expect(newShop.isRecordDay, isFalse); // not enough history to mean anything
    });
  });

  group('AppIconService', () {
    late List<MethodCall> calls;
    late String active;
    late MethodChannel channel;
    var now = DateTime(2026, 10, 16, 10);
    var signals = _s();

    AppIconService service() => AppIconService(
          channel: channel,
          clock: () => now,
          signalsLoader: (_, __) async => signals,
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      calls = [];
      active = 'standard';
      now = DateTime(2026, 10, 16, 10);
      signals = _s();
      channel = const MethodChannel('axon_pos/app_icon');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
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

    int switches() => calls.where((c) => c.method == 'setIcon').length;

    test(
      'is on by default and follows the shop on the next background',
      () async {
        signals = _s(record: true);
        final svc = service();
        expect(await svc.isEnabled(), isTrue);
        expect(await svc.refresh(), AppIconVariant.gold);
        expect(active, 'gold');
        expect(switches(), 1);
      },
    );

    test('turning it on does not touch the icon while the app is open', () async {
      signals = _s(streak: 4);
      final svc = service();
      await svc.setEnabled(true);
      expect(await svc.isEnabled(), isTrue);
      expect(switches(), 0, reason: 'switching in the foreground closes the app');
      expect(active, 'standard');
    });

    test('the change lands when the app goes to the background', () async {
      signals = _s(streak: 4);
      final svc = service();
      await svc.setEnabled(true);
      expect(await svc.refresh(), AppIconVariant.streak);
      expect(active, 'streak');
    });

    test('turning it off restores the everyday icon on the next background', () async {
      signals = _s(streak: 4);
      final svc = service();
      await svc.setEnabled(true);
      await svc.refresh();
      await svc.setEnabled(false);
      expect(active, 'streak', reason: 'still deferred');
      expect(await svc.refresh(), AppIconVariant.standard);
      expect(active, 'standard');
    });

    test('does nothing when the icon is already right', () async {
      final svc = service();
      await svc.setEnabled(true);
      await svc.refresh();
      expect(switches(), 0);
    });

    test('changes at most once per gap, then follows the shop again', () async {
      signals = _s(streak: 4);
      final svc = service();
      await svc.setEnabled(true);
      await svc.refresh();
      expect(active, 'streak');

      now = now.add(const Duration(hours: 2));
      signals = _s(outOfStock: 2);
      await svc.refresh();
      expect(active, 'streak', reason: 'too soon to change again');

      now = now.add(const Duration(hours: 19));
      await svc.refresh();
      expect(active, 'alert');
    });

    test('can pin the current icon to the home screen', () async {
      expect(await service().pinCurrentIcon(), isTrue);
      expect(calls.single.method, 'pinCurrentIcon');
    });

    test('a phone without the native side is tolerated', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      signals = _s(streak: 4);
      final svc = service();
      expect(await svc.current(), AppIconVariant.standard);
      expect(await svc.pinCurrentIcon(), isFalse);
      await svc.setEnabled(true);
      await svc.refresh(); // must not throw
    });
  });
}
