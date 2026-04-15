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
  StreamSubscription<ConnectivityResult>? _subscription;
  
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus get currentStatus => _currentStatus;
  bool get isOnline => _currentStatus == ConnectionStatus.online;
  bool get isOffline => _currentStatus == ConnectionStatus.offline;
  
  void initialize() {
    _checkConnectivity();
    _subscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }
  
  Future<void> _checkConnectivity() async {
    await checkCurrentStatus();
  }

  Future<ConnectionStatus> checkCurrentStatus() async {
    final result = await _connectivity.checkConnectivity();
    final connectivityResult = _normalizeConnectivityResult(result);
    _setStatus(_mapStatus(connectivityResult));
    return _currentStatus;
  }
  
  void _onConnectivityChanged(ConnectivityResult result) {
    _setStatus(_mapStatus(result));
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
    final hasConnection = 
      result == ConnectivityResult.mobile || 
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.ethernet
    ;

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
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  throw UnimplementedError('Must be overridden');
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
