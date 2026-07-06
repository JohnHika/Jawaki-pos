import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axon_pos/features/clients/data/models/branch.dart';
import 'package:axon_pos/features/clients/data/models/pos_client.dart';

/// Client List Provider - Manages the list of POS clients
final clientsProvider = StateNotifierProvider<ClientsNotifier, List<PosClient>>((ref) {
  return ClientsNotifier();
});

/// Clients Notifier - Manages client state with Riverpod
class ClientsNotifier extends StateNotifier<List<PosClient>> {
  ClientsNotifier() : super([]);

  /// Get all clients
  List<PosClient> get allClients => state;

  /// Get active clients
  List<PosClient> get activeClients => state.where((c) => c.isActive).toList();

  /// Get clients with issues
  List<PosClient> get clientsWithIssues => state.where((c) => c.hasIssues).toList();

  /// Add a new client
  void addClient(PosClient client) {
    state = [...state, client];
  }

  /// Update an existing client
  void updateClient(PosClient client) {
    state = [
      for (final c in state)
        if (c.id == client.id) client
        else c,
    ];
  }

  /// Toggle client active status
  void toggleClientActive(String clientId) {
    state = [
      for (final c in state)
        if (c.id == clientId)
          c.copyWith(isActive: !c.isActive)
        else c,
    ];
  }

  /// Delete a client
  void deleteClient(String clientId) {
    state = state.where((c) => c.id != clientId).toList();
  }

  /// Get client by ID
  PosClient? getClientById(String id) {
    try {
      return state.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Client Detail Provider - Manages a specific client and its branches
final clientDetailProvider = StateNotifierProvider<ClientDetailNotifier, Map<String, dynamic>>((ref) {
  return ClientDetailNotifier();
});

/// Client Detail Notifier
class ClientDetailNotifier extends StateNotifier<Map<String, dynamic>> {
  ClientDetailNotifier() : super({'client': null, 'branches': <Branch>[]});

  /// Set the current client
  void setClient(PosClient? client) {
    state = {...state, 'client': client};
  }

  /// Set branches for the current client
  void setBranches(List<Branch> branches) {
    state = {...state, 'branches': branches};
  }

  /// Update a branch
  void updateBranch(Branch branch) {
    final branches = List<Branch>.from(state['branches'] ?? []);
    state = {
      ...state,
      'branches': [
        for (final b in branches)
          if (b.id == branch.id) branch
          else b,
      ],
    };
  }

  /// Add a new branch
  void addBranch(Branch branch) {
    final branches = List<Branch>.from(state['branches'] ?? []);
    state = {
      ...state,
      'branches': [...branches, branch],
    };
  }

  /// Delete a branch
  void deleteBranch(String branchId) {
    final branches = List<Branch>.from(state['branches'] ?? []);
    state = {
      ...state,
      'branches': branches.where((b) => b.id != branchId).toList(),
    };
  }
}

/// Branch List Provider for a specific client
final clientBranchesProvider = Provider<List<Branch>>((ref) {
  final detail = ref.watch(clientDetailProvider);
  return (detail['branches'] as List<Branch>) ?? [];
});

/// Selected Client Provider - For passing client between screens
final selectedClientProvider = StateProvider<PosClient?>((ref) => null);

/// Clients with Issues Counter - For badge on navigation
final clientsWithIssuesCounterProvider = Provider<int>((ref) {
  final clients = ref.watch(clientsProvider);
  return clients.where((c) => c.hasIssues).length;
});

/// Dashboard Summary Provider - For multi-client dashboard
final dashboardSummaryProvider = Provider<Map<String, dynamic>>((ref) {
  final clients = ref.watch(clientsProvider);
  
  final totalClients = clients.length;
  final activeSubscriptions = clients.where((c) => c.isSubscriptionActive).length;
  final trialClients = clients.where((c) => c.subscriptionStatus == 'trial').length;
  final expiredClients = clients.where((c) => c.subscriptionStatus == 'expired').length;
  
  // Calculate total pending payments
  double totalPendingPayments = 0;
  for (final c in clients) {
    if (c.pendingPayments != null) {
      totalPendingPayments += c.pendingPayments!;
    }
  }

  return {
    'totalClients': totalClients,
    'activeSubscriptions': activeSubscriptions,
    'trialClients': trialClients,
    'expiredClients': expiredClients,
    'totalPendingPayments': totalPendingPayments,
  };
});
