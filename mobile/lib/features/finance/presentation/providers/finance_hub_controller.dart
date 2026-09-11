import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../data/finance_repository.dart';
import '../../domain/finance_models.dart';

final financeHubProvider =
    StateNotifierProvider.autoDispose<FinanceHubController, FinanceHubState>(
  (ref) {
    final auth = getIt<AuthService>();
    final tenantId = auth.tenantId;
    final branchId = auth.branchId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        branchId == null ||
        branchId.isEmpty) {
      return FinanceHubController.unavailable();
    }
    return FinanceHubController(
      source: _LiveFinanceHubDataSource(
        repository: FinanceRepository(
          apiClient: getIt<ApiClient>(),
          storage: getIt<StorageService>(),
          tenantId: tenantId,
        ),
        apiClient: getIt<ApiClient>(),
      ),
      tenantId: tenantId,
      branchId: branchId,
    );
  },
);

class FinanceHubState {
  const FinanceHubState({
    this.snapshot,
    this.isRefreshing = false,
    this.errorMessage,
  });

  final FinanceSnapshot? snapshot;
  final bool isRefreshing;
  final String? errorMessage;

  bool get hasSnapshot => snapshot != null;
  bool get canRetry => errorMessage != null;
  bool get hasInitialError => !hasSnapshot && errorMessage != null;

  FinanceHubState copyWith({
    FinanceSnapshot? snapshot,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) =>
      FinanceHubState(
        snapshot: snapshot ?? this.snapshot,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

class PeerReceivableRequest {
  const PeerReceivableRequest({
    required this.branchId,
    required this.debtorId,
    required this.description,
    required this.amount,
    this.dueDate,
  });

  final String branchId;
  final String debtorId;
  final String description;
  final double amount;
  final DateTime? dueDate;
}

class ReceivableCollectionRequest {
  const ReceivableCollectionRequest({
    required this.receivableId,
    required this.branchId,
    required this.amount,
    required this.method,
    this.reference,
  });

  final String receivableId;
  final String branchId;
  final double amount;
  final String method;
  final String? reference;
}

abstract class FinanceHubDataSource {
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId);
  Future<FinanceSnapshot> refresh(String branchId);
  Future<void> createPeerDebtor({required String name, String? contact});
  Future<void> createPeerReceivable(PeerReceivableRequest request);
  Future<void> recordRetailCollection(ReceivableCollectionRequest request);
  Future<void> recordPeerCollection(ReceivableCollectionRequest request);
}

class FinanceHubController extends StateNotifier<FinanceHubState> {
  FinanceHubController({
    required FinanceHubDataSource source,
    required String tenantId,
    required String branchId,
  })  : _source = source,
        _branchId = branchId,
        super(FinanceHubState(
          snapshot: source.loadCachedSnapshot(tenantId, branchId),
          isRefreshing: true,
        )) {
    unawaited(refresh());
  }

  FinanceHubController.unavailable()
      : _source = null,
        _branchId = '',
        super(const FinanceHubState(
          errorMessage:
              'Finance needs a selected branch. Choose a branch and retry.',
        ));

  final FinanceHubDataSource? _source;
  final String _branchId;

  Future<void> refresh() async {
    final source = _source;
    if (source == null) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final snapshot = await source.refresh(_branchId);
      if (!mounted) return;
      state = FinanceHubState(snapshot: snapshot);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: state.hasSnapshot
            ? 'Couldn’t refresh — showing saved figures'
            : 'Couldn’t load Finance. Reconnect and try again.',
      );
    }
  }

  Future<void> createPeerDebtor({required String name, String? contact}) async {
    if (name.trim().isEmpty) {
      throw const FinanceFormException('Shop name is required');
    }
    final source = _requireSource();
    await source.createPeerDebtor(
        name: name.trim(), contact: _optional(contact));
    await refresh();
  }

  Future<void> createPeerReceivable(PeerReceivableRequest request) async {
    if (_branchId.isEmpty || request.branchId.trim().isEmpty) {
      throw const FinanceFormException('Branch is required');
    }
    if (request.debtorId.trim().isEmpty) {
      throw const FinanceFormException('Select a shop');
    }
    if (request.description.trim().isEmpty) {
      throw const FinanceFormException('Description is required');
    }
    if (request.amount <= 0) {
      throw const FinanceFormException('Amount must be greater than zero');
    }
    await _requireSource().createPeerReceivable(request);
    await refresh();
  }

  Future<void> recordRetailCollection(
      ReceivableCollectionRequest request) async {
    _validateCollection(request);
    await _requireSource().recordRetailCollection(request);
    await refresh();
  }

  Future<void> recordPeerCollection(ReceivableCollectionRequest request) async {
    _validateCollection(request);
    await _requireSource().recordPeerCollection(request);
    await refresh();
  }

  FinanceHubDataSource _requireSource() {
    final source = _source;
    if (source == null) {
      throw const FinanceFormException('Branch is required');
    }
    return source;
  }

  void _validateCollection(ReceivableCollectionRequest request) {
    if (request.branchId.trim().isEmpty || _branchId.isEmpty) {
      throw const FinanceFormException('Branch is required');
    }
    if (request.amount <= 0) {
      throw const FinanceFormException('Amount must be greater than zero');
    }
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class FinanceFormException implements Exception {
  const FinanceFormException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _LiveFinanceHubDataSource implements FinanceHubDataSource {
  _LiveFinanceHubDataSource({
    required FinanceRepository repository,
    required ApiClient apiClient,
  })  : _repository = repository,
        _apiClient = apiClient;

  final FinanceRepository _repository;
  final ApiClient _apiClient;

  @override
  FinanceSnapshot? loadCachedSnapshot(String tenantId, String branchId) =>
      _repository.loadCachedSnapshot(tenantId, branchId);

  @override
  Future<FinanceSnapshot> refresh(String branchId) =>
      _repository.refresh(branchId);

  @override
  Future<void> createPeerDebtor({required String name, String? contact}) async {
    await _apiClient.createPeerDebtor(name: name, contactName: contact);
  }

  @override
  Future<void> createPeerReceivable(PeerReceivableRequest request) async {
    await _apiClient.createPeerReceivable(
      branchId: request.branchId,
      debtorId: request.debtorId,
      description: request.description,
      amount: request.amount,
      dueDate: request.dueDate?.toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> recordRetailCollection(
      ReceivableCollectionRequest request) async {
    await _apiClient.recordRetailReceivablePayment(
      receivableId: request.receivableId,
      branchId: request.branchId,
      amount: request.amount,
      method: request.method,
      reference: request.reference,
    );
  }

  @override
  Future<void> recordPeerCollection(ReceivableCollectionRequest request) async {
    await _apiClient.recordPeerReceivablePayment(
      receivableId: request.receivableId,
      branchId: request.branchId,
      amount: request.amount,
      method: request.method,
      reference: request.reference,
    );
  }
}
