import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/partner_models.dart';

/// Turns an API failure into a sentence a shop owner can act on.
String partnerErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) return message.first.toString();
    }
    final status = error.response?.statusCode;
    if (status == 403) return "You don't have permission to do that.";
    if (status == 404) return 'That was not found.';
    if (status != null && status >= 500) {
      return 'Server error. Please try again in a moment.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return "Couldn't reach the server. Check your internet and try again.";
    }
  }
  return 'Something went wrong. Please try again.';
}

class PartnersState {
  const PartnersState({
    this.partners = const [],
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final List<TradePartner> partners;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  List<TradePartner> get incomingRequests =>
      partners.where((p) => p.isIncomingRequest).toList();
  List<TradePartner> get outgoingRequests =>
      partners.where((p) => p.isOutgoingRequest).toList();
  List<TradePartner> get connected =>
      partners.where((p) => p.isAccepted).toList();
  int get unreadMessages => connected.fold(0, (sum, p) => sum + p.unreadCount);

  TradePartner? byId(String id) {
    for (final p in partners) {
      if (p.id == id) return p;
    }
    return null;
  }

  PartnersState copyWith({
    List<TradePartner>? partners,
    bool? isLoading,
    bool? loadedOnce,
    String? error,
    bool clearError = false,
  }) =>
      PartnersState(
        partners: partners ?? this.partners,
        isLoading: isLoading ?? this.isLoading,
        loadedOnce: loadedOnce ?? this.loadedOnce,
        error: clearError ? null : (error ?? this.error),
      );
}

class PartnersController extends StateNotifier<PartnersState> {
  PartnersController() : super(const PartnersState()) {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
    refresh();
  }

  Timer? _timer;

  ApiClient get _api => getIt<ApiClient>();

  Future<void> refresh() async {
    if (state.isLoading) return;
    // Keep any earlier error showing while a retry is in flight: clearing it
    // here made the page flip back to the neutral "no partners yet" text
    // every 30 seconds, hiding the fact the load had actually failed.
    state = state.copyWith(isLoading: true);
    try {
      final rows = await _api.getTradePartners();
      state = state.copyWith(
        partners: rows.map(TradePartner.fromJson).toList(),
        isLoading: false,
        loadedOnce: true,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        loadedOnce: true,
        error: partnerErrorMessage(e),
      );
    }
  }

  /// Sends a connection request. Throws with a friendly message on failure.
  Future<void> connect(String companyCode, {String? message}) async {
    try {
      await _api.requestTradePartner(
          companyCode: companyCode.trim().toLowerCase(), message: message);
    } catch (e) {
      throw PartnerActionException(partnerErrorMessage(e));
    }
    await _reload();
  }

  Future<void> accept(String id) => _act(() => _api.acceptTradePartner(id));
  Future<void> decline(String id) => _act(() => _api.declineTradePartner(id));
  Future<void> remove(String id) => _act(() => _api.removeTradePartner(id));

  Future<void> _act(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      throw PartnerActionException(partnerErrorMessage(e));
    }
    await _reload();
  }

  Future<void> _reload() async {
    state = state.copyWith(isLoading: false);
    await refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class PartnerActionException implements Exception {
  const PartnerActionException(this.message);
  final String message;

  @override
  String toString() => message;
}

final partnersProvider =
    StateNotifierProvider<PartnersController, PartnersState>(
  (ref) => PartnersController(),
);
