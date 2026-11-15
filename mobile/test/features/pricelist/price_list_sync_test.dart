import 'dart:async';

import 'package:axon_pos/core/cache/swr_cache.dart';
import 'package:axon_pos/features/pricelist/presentation/providers/price_list_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PriceListSync _sync({
  required Future<void> Function() run,
  bool deviceOnly = false,
  DateTime Function()? clock,
}) =>
    PriceListSync(
      sync: run,
      deviceOnly: deviceOnly,
      scopeKey: 'shop:branch',
      cache: SwrCache(namespace: 'pl_sync_test', softTtl: Duration.zero),
      clock: clock,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a refresh asks the server and records when it was confirmed', () async {
    var calls = 0;
    final now = DateTime(2026, 11, 15, 10);
    final sync = _sync(run: () async => calls++, clock: () => now);

    expect(await sync.refresh(), isTrue);

    expect(calls, 1);
    expect(sync.state.lastSyncedAt, now);
    expect(sync.state.lastFailed, isFalse);
    expect(sync.state.syncing, isFalse);
  });

  test('a failed refresh keeps the last good time and says it failed', () async {
    var fail = false;
    final then = DateTime(2026, 11, 15, 10);
    var clock = then;
    final sync = _sync(
      run: () async {
        if (fail) throw StateError('offline');
      },
      clock: () => clock,
    );
    await sync.refresh();

    fail = true;
    clock = then.add(const Duration(hours: 1));
    expect(await sync.refresh(), isFalse);

    expect(sync.state.lastFailed, isTrue);
    expect(sync.state.syncing, isFalse);
    expect(sync.state.lastSyncedAt, then);

    fail = false;
    expect(await sync.refresh(), isTrue);
    expect(sync.state.lastFailed, isFalse);
  });

  test('two taps share one request', () async {
    final gate = Completer<void>();
    var calls = 0;
    final sync = _sync(run: () {
      calls++;
      return gate.future;
    });

    final first = sync.refresh();
    final second = sync.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(sync.state.syncing, isTrue);
    gate.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(calls, 1);
  });

  test('a shop that keeps prices on the phone never calls the server', () async {
    var calls = 0;
    final sync = _sync(run: () async => calls++, deviceOnly: true);

    expect(await sync.refresh(), isTrue);
    await sync.syncIfStale();

    expect(calls, 0);
    expect(sync.state.deviceOnly, isTrue);
    expect(sync.state.lastSyncedAt, isNull);
  });

  test('opening the page refreshes only when the prices are old', () async {
    var calls = 0;
    var clock = DateTime(2026, 11, 15, 10);
    final sync = _sync(run: () async => calls++, clock: () => clock);

    await sync.syncIfStale();
    expect(calls, 1);

    clock = clock.add(const Duration(minutes: 2));
    await sync.syncIfStale();
    expect(calls, 1, reason: 'confirmed two minutes ago');

    clock = clock.add(const Duration(minutes: 10));
    await sync.syncIfStale();
    expect(calls, 2);
  });

  test('the time of the last sync is still known after the app restarts',
      () async {
    final first = _sync(run: () async {});
    await first.refresh();

    final second = _sync(run: () async {});
    await second.syncIfStale(); // waits for the saved time to load
    expect(second.state.lastSyncedAt, isNotNull);
  });
}
