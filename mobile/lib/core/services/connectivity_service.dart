import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus {
  online,
  offline,
}

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _currentStatus = ConnectionStatus.offline;
  ConnectivityResult _currentConnectivity = ConnectivityResult.none;
  StreamSubscription<dynamic>? _subscription;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus get currentStatus => _currentStatus;
  ConnectivityResult get currentConnectivity => _currentConnectivity;
  bool get isOnline => _currentStatus == ConnectionStatus.online;
  bool get isOffline => _currentStatus == ConnectionStatus.offline;
  bool get isWifi => _currentConnectivity == ConnectivityResult.wifi;

  Future<void> initialize() async {
    // This runs in main() before runApp() — if the platform channel call
    // inside checkCurrentStatus ever stalled (seen on some devices/OEMs,
    // e.g. right after boot or under battery-optimization restrictions),
    // an unbounded await here would freeze the entire app before a single
    // frame renders, not just one screen. checkCurrentStatus now times out
    // and degrades to offline internally, so this always proceeds; the
    // real status still arrives moments later via onConnectivityChanged.
    await _checkConnectivity();
    _subscription =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }

  Future<void> _checkConnectivity() async {
    await checkCurrentStatus();
  }

  /// Never hangs and never throws: every existing caller (app startup,
  /// background sync, foreground sync retries) already treats a plain
  /// [ConnectionStatus.offline] as "skip for now," so a stalled platform
  /// channel call safely degrades to that same outcome instead of needing
  /// every call site updated to handle a new exception.
  Future<ConnectionStatus> checkCurrentStatus() async {
    try {
      final result = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 5));
      final connectivityResult = _normalizeConnectivityResult(result);
      _currentConnectivity = connectivityResult;
      _setStatus(_mapStatus(connectivityResult));
    } on TimeoutException {
      _currentConnectivity = ConnectivityResult.none;
      _setStatus(ConnectionStatus.offline);
    }
    return _currentStatus;
  }

  void _onConnectivityChanged(dynamic result) {
    final connectivityResult = _normalizeConnectivityResult(result);
    _currentConnectivity = connectivityResult;
    _setStatus(_mapStatus(connectivityResult));
  }

  ConnectivityResult _normalizeConnectivityResult(Object? result) {
    if (result is List<ConnectivityResult> && result.isNotEmpty) {
      return result.first;
    }

    if (result is ConnectivityResult) {
      return result;
    }

    return ConnectivityResult.none;
  }

  ConnectionStatus _mapStatus(ConnectivityResult result) {
    final hasConnection = result == ConnectivityResult.mobile ||
        result == ConnectivityResult.wifi ||
        result == ConnectivityResult.ethernet;

    return hasConnection ? ConnectionStatus.online : ConnectionStatus.offline;
  }

  void _setStatus(ConnectionStatus newStatus) {
    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _statusController.add(_currentStatus);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
  }
}

// Riverpod providers
// NOTE: The actual ConnectivityService instance is created in injection.dart
// This provider is a fallback that should not be used in production
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  // This should never be called in production as the service is registered in GetIt
  // If you hit this error, make sure injection.dart is properly configured
  throw StateError(
    'ConnectivityService accessed via Riverpod before DI initialization. '
    'Use getIt<ConnectivityService>() instead, or ensure configureDependencies() is called first.',
  );
});

final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.statusStream;
});

final isOnlineProvider = Provider<bool>((ref) {
  final status = ref.watch(connectionStatusProvider);
  return status.maybeWhen(
    data: (s) => s == ConnectionStatus.online,
    orElse: () => false,
  );
});
