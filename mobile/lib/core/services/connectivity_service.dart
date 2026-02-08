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
    final result = await _connectivity.checkConnectivity();
    _onConnectivityChanged(result is List ? (result as List<ConnectivityResult>).first : result as ConnectivityResult);
  }
  
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasConnection = 
      result == ConnectivityResult.mobile || 
      result == ConnectivityResult.wifi ||
      result == ConnectivityResult.ethernet
    ;
    
    final newStatus = hasConnection ? ConnectionStatus.online : ConnectionStatus.offline;
    
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
