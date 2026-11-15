import 'dart:async';

import 'package:axon_pos/core/cache/swr_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  SwrCache cache({int version = 1}) => SwrCache(
        namespace: 'test',
        schemaVersion: version,
        softTtl: const Duration(minutes: 5),
        hardTtl: const Duration(days: 1),
        clock: () => now,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 15, 9);
  });

  test('with nothing saved it fetches, saves, and emits the fresh value', () async {
    final c = cache();
    final out = await c.watch<Map>('prices', fetch: () async => {'a': 1}).toList();

    expect(out.last.value, {'a': 1});
    expect(out.last.fromCache, isFalse);
    expect((await c.read('prices'))!.json, {'a': 1});
  });

  test('a fresh copy is shown and no request is made', () async {
    final c = cache();
    await c.write('prices', {'a': 1});
    var calls = 0;

    final out = await c.watch<Map>('prices', fetch: () async {
      calls++;
      return {'a': 2};
    }).toList();

    expect(calls, 0);
    expect(out.single.value, {'a': 1});
    expect(out.single.fromCache, isTrue);
  });

  test('a stale copy is shown first, then replaced when the data changed', () async {
    final c = cache();
    await c.write('prices', {'a': 1});
    now = now.add(const Duration(minutes: 30));

    final out = await c.watch<Map>('prices', fetch: () async => {'a': 2}).toList();

    expect(out.first.value, {'a': 1});
    expect(out.first.fromCache, isTrue);
    expect(out.first.refreshing, isTrue);
    expect(out.last.value, {'a': 2});
    expect(out.last.fromCache, isFalse);
  });

  test('the screen keeps its copy when the refresh returns the same data', () async {
    final c = cache();
    await c.write('prices', {'a': 1});
    now = now.add(const Duration(minutes: 30));

    final out = await c.watch<Map>('prices', fetch: () async => {'a': 1}).toList();

    expect(out.length, 2);
    // Same value object content; confirmed, not redrawn as new.
    expect(out.last.value, {'a': 1});
    expect(out.last.fromCache, isFalse);
  });

  test('a failed refresh keeps the last good copy and reports the error', () async {
    final c = cache();
    await c.write('prices', {'a': 1});
    now = now.add(const Duration(minutes: 30));

    final out = await c
        .watch<Map>('prices', fetch: () async => throw StateError('offline'))
        .toList();

    expect(out.last.value, {'a': 1});
    expect(out.last.error, isA<StateError>());
    expect((await c.read('prices'))!.json, {'a': 1});
  });

  test('with nothing saved a failed refresh reports the error and no value', () async {
    final c = cache();
    final out = await c
        .watch<Map>('prices', fetch: () async => throw StateError('offline'))
        .toList();

    expect(out.last.hasValue, isFalse);
    expect(out.last.error, isNotNull);
  });

  test('a copy past the hard limit is dropped, not shown', () async {
    final c = cache();
    await c.write('prices', {'a': 1});
    now = now.add(const Duration(days: 2));

    expect(await c.read('prices'), isNull);
  });

  test('a copy written by another schema version is ignored', () async {
    await cache(version: 1).write('prices', {'a': 1});

    expect(await cache(version: 2).read('prices'), isNull);
  });

  test('two screens asking at once share one request', () async {
    final c = cache();
    final gate = Completer<Map>();
    var calls = 0;
    Future<Map> fetch() {
      calls++;
      return gate.future;
    }

    final a = c.watch<Map>('prices', fetch: fetch).toList();
    final b = c.watch<Map>('prices', fetch: fetch).toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate.complete({'a': 1});
    final results = await Future.wait([a, b]);

    expect(calls, 1);
    expect(results[0].last.value, {'a': 1});
    expect(results[1].last.value, {'a': 1});
  });

  test('force refreshes a fresh copy', () async {
    final c = cache();
    await c.write('prices', {'a': 1});

    final out = await c
        .watch<Map>('prices', fetch: () async => {'a': 2}, force: true)
        .toList();

    expect(out.last.value, {'a': 2});
  });

  test('a copy the decoder cannot read is treated as missing', () async {
    final c = cache();
    await c.write('prices', {'bad': true});

    final out = await c.watch<int>(
      'prices',
      fetch: () async => 7,
      fromJson: (json) => (json as Map)['a'] as int,
    ).toList();

    expect(out.last.value, 7);
  });

  test('clear removes only this namespace', () async {
    final c = cache();
    final other = SwrCache(namespace: 'other', clock: () => now);
    await c.write('a', 1);
    await other.write('a', 2);

    await c.clear();

    expect(await c.read('a'), isNull);
    expect((await other.read('a'))!.json, 2);
  });
}
