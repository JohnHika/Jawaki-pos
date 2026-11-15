import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a [SwrCache.watch] stream tells a screen.
class SwrSnapshot<T> {
  const SwrSnapshot({
    this.value,
    this.fromCache = false,
    this.refreshing = false,
    this.error,
    this.savedAt,
  });

  /// The newest value known: the saved copy first, the fresh one after.
  final T? value;

  /// True while [value] is the copy kept on the phone, not yet confirmed.
  final bool fromCache;

  /// True while a refresh is running in the background.
  final bool refreshing;

  /// Set when the last refresh failed. [value] is still the last good copy.
  final Object? error;

  /// When [value] was fetched.
  final DateTime? savedAt;

  bool get hasValue => value != null;

  @override
  String toString() =>
      'SwrSnapshot(hasValue: $hasValue, fromCache: $fromCache, refreshing: $refreshing, error: $error)';
}

/// Stale-while-revalidate storage on the phone, with no database.
///
/// Why: a screen that waits for the server every time it opens feels slow on
/// every network. This keeps the last good copy of read-heavy data (price list,
/// plan, entitlement) in SharedPreferences, shows it at once, and refreshes in
/// the background.
///
/// - **Soft TTL** ([softTtl]): younger than this, the copy is fresh and no
///   request is made. Older, it is still shown, and a refresh starts.
/// - **Hard TTL** ([hardTtl]): older than this, the copy is dropped, not shown.
/// - **Schema version** ([schemaVersion]): a copy written by another version of
///   the app's data shape is ignored, so a changed model never crashes on old
///   JSON. Bump it whenever the shape of what you store changes.
/// - **Coalescing**: two screens asking for the same key at once share a
///   single request.
/// - **Redraw only if changed**: the fresh value is emitted only when its JSON
///   differs from what the screen already shows.
/// - **Keep last good**: a failed refresh never clears the copy; it is reported
///   in [SwrSnapshot.error] beside the old value.
///
/// Values must be JSON-encodable (maps, lists, strings, numbers, bools), or
/// pass `toJson` / `fromJson`. Scope keys per shop (include the tenant id), so
/// another shop signing in on the same phone never sees this one's data.
class SwrCache {
  SwrCache({
    required this.namespace,
    this.schemaVersion = 1,
    this.softTtl = const Duration(minutes: 5),
    this.hardTtl = const Duration(days: 7),
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _now = clock ?? DateTime.now;

  final String namespace;
  final int schemaVersion;
  final Duration softTtl;
  final Duration hardTtl;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;

  /// One request per key at a time, shared by every caller.
  final Map<String, Future<Object?>> _inFlight = {};

  String _storageKey(String key) => 'swr:$namespace:$key';

  /// The saved copy, or null when there is none, it is too old, or it was
  /// written by another [schemaVersion].
  Future<SwrEntry?> read(String key) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_storageKey(key));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map || map['v'] != schemaVersion) {
        await prefs.remove(_storageKey(key));
        return null;
      }
      final savedAt = DateTime.fromMillisecondsSinceEpoch(map['t'] as int);
      final age = _now().difference(savedAt);
      if (age > hardTtl) {
        await prefs.remove(_storageKey(key));
        return null;
      }
      return SwrEntry(map['d'], savedAt, stale: age > softTtl);
    } catch (_) {
      await prefs.remove(_storageKey(key));
      return null;
    }
  }

  /// Saves [value] as the newest copy.
  Future<void> write(String key, Object? value) async {
    final prefs = await _prefs();
    await prefs.setString(
      _storageKey(key),
      jsonEncode({'v': schemaVersion, 't': _now().millisecondsSinceEpoch, 'd': value}),
    );
  }

  Future<void> remove(String key) async {
    final prefs = await _prefs();
    await prefs.remove(_storageKey(key));
  }

  /// Removes everything in this namespace (sign-out, or switching shop).
  Future<void> clear() async {
    final prefs = await _prefs();
    final prefix = 'swr:$namespace:';
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
  }

  /// Loads [key]: emits the saved copy at once (if any), then refreshes with
  /// [fetch] when the copy is missing, stale, or [force] is true, and emits the
  /// fresh value only if it differs. Completes after the refresh.
  Stream<SwrSnapshot<T>> watch<T>(
    String key, {
    required Future<T> Function() fetch,
    Object? Function(T value)? toJson,
    T Function(Object? json)? fromJson,
    bool force = false,
  }) async* {
    T decode(Object? json) => fromJson != null ? fromJson(json) : json as T;
    Object? encode(T value) => toJson != null ? toJson(value) : value;

    T? current;
    String? currentJson;
    DateTime? savedAt;
    var shouldFetch = true;

    final cached = await read(key);
    if (cached != null) {
      try {
        current = decode(cached.json);
        currentJson = jsonEncode(cached.json);
        savedAt = cached.savedAt;
        shouldFetch = force || cached.stale;
        yield SwrSnapshot<T>(
          value: current,
          fromCache: true,
          refreshing: shouldFetch,
          savedAt: savedAt,
        );
      } catch (_) {
        // A copy the current code cannot read is as good as none.
        await remove(key);
        current = null;
        currentJson = null;
        savedAt = null;
        shouldFetch = true;
      }
    }
    if (!shouldFetch) return;
    if (current == null) {
      yield SwrSnapshot<T>(refreshing: true);
    }

    try {
      final fresh = await refresh<T>(key, fetch: fetch, toJson: toJson);
      final freshJson = jsonEncode(encode(fresh));
      if (freshJson != currentJson || current == null) {
        yield SwrSnapshot<T>(value: fresh, savedAt: _now());
      } else {
        // Nothing changed: the screen keeps what it has, now confirmed.
        yield SwrSnapshot<T>(value: current, savedAt: _now());
      }
    } catch (error) {
      yield SwrSnapshot<T>(
        value: current,
        fromCache: current != null,
        error: error,
        savedAt: savedAt,
      );
    }
  }

  /// Runs [fetch] once per key at a time and saves the result. Concurrent calls
  /// for the same key return the same future.
  Future<T> refresh<T>(
    String key, {
    required Future<T> Function() fetch,
    Object? Function(T value)? toJson,
  }) {
    final running = _inFlight[key];
    if (running != null) return running.then((v) => v as T);
    final future = () async {
      final value = await fetch();
      await write(key, toJson != null ? toJson(value) : value);
      return value as Object?;
    }();
    _inFlight[key] = future;
    future.whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }).ignore();
    return future.then((v) => v as T);
  }
}

/// A saved copy and how old it is.
class SwrEntry {
  const SwrEntry(this.json, this.savedAt, {required this.stale});

  final Object? json;
  final DateTime savedAt;

  /// Past the soft TTL: show it, and refresh.
  final bool stale;
}
