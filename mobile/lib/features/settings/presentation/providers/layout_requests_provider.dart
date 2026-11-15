import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// One request to change the shop's business type, as the shop sees it.
class LayoutChangeRequest {
  const LayoutChangeRequest({
    required this.id,
    required this.toProfileId,
    required this.additionalProfileIds,
    required this.reason,
    required this.status,
    this.fromProfileId,
    this.decisionNote,
    this.createdAt,
  });

  final String id;
  final String? fromProfileId;
  final String toProfileId;
  final List<String> additionalProfileIds;
  final String reason;

  /// PENDING | APPROVED | REJECTED | CANCELLED
  final String status;
  final String? decisionNote;
  final DateTime? createdAt;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  factory LayoutChangeRequest.fromJson(Map<String, dynamic> json) {
    final extras = json['additionalProfileIds'];
    return LayoutChangeRequest(
      id: json['id']?.toString() ?? '',
      fromProfileId: json['fromProfileId']?.toString(),
      toProfileId: json['toProfileId']?.toString() ?? '',
      additionalProfileIds:
          extras is List ? extras.map((e) => e.toString()).toList() : const [],
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      decisionNote: json['decisionNote']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

/// Talks to the shop's change-request endpoints. Errors carry a message that
/// is safe to show the owner.
class LayoutRequestsApi {
  LayoutRequestsApi(this._dio);
  final Dio _dio;

  Future<List<LayoutChangeRequest>> list() async {
    final response = await _dio.get('/branches/layout-requests');
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => LayoutChangeRequest.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<LayoutChangeRequest> create({
    required String toProfileId,
    List<String> additionalProfileIds = const [],
    required String reason,
  }) async {
    final response = await _dio.post('/branches/layout-requests', data: {
      'toProfileId': toProfileId,
      'additionalProfileIds': additionalProfileIds,
      'reason': reason,
    });
    return LayoutChangeRequest.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> cancel(String id) async {
    await _dio.post('/branches/layout-requests/$id/cancel');
  }

  /// Plain-language message for a failed call.
  static String messageFor(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      final message = data is Map ? data['message'] : null;
      if (message is List && message.isNotEmpty) return message.first.toString();
      if (message is String && message.isNotEmpty) return message;
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'No connection. Check your internet and try again.';
      }
    }
    return 'That did not go through. Please try again.';
  }
}

final layoutRequestsApiProvider =
    Provider<LayoutRequestsApi>((ref) => LayoutRequestsApi(getIt<Dio>()));

/// The shop's requests, newest first. Empty for a device-only shop.
final layoutRequestsProvider =
    FutureProvider.autoDispose<List<LayoutChangeRequest>>((ref) async {
  if (getIt<AuthService>().isLocalWorkspace) return const [];
  return ref.watch(layoutRequestsApiProvider).list();
});

/// Whether this shop's business type is fixed to what it paid for.
class BusinessTypeLock {
  const BusinessTypeLock({
    required this.locked,
    this.approvedProfileId,
    this.approvedAdditionalProfileIds = const [],
  });

  /// Free choice: a trial, a first-time setup or a device-only shop.
  const BusinessTypeLock.free()
      : locked = false,
        approvedProfileId = null,
        approvedAdditionalProfileIds = const [];

  final bool locked;

  /// Set when the team approved a change that the owner has not applied yet.
  final String? approvedProfileId;
  final List<String> approvedAdditionalProfileIds;

  bool get hasApproval => approvedProfileId != null;
}

/// Mirrors the server rule: a paid shop that already has a business type keeps
/// it, unless a change was approved. The server enforces it; this only decides
/// what the screen offers.
BusinessTypeLock businessTypeLockFor(
  Map<String, dynamic>? user, {
  required bool isLocalWorkspace,
}) {
  if (isLocalWorkspace) return const BusinessTypeLock.free();
  final tenant = user?['tenant'];
  if (tenant is! Map || tenant['activationStatus']?.toString() != 'ACTIVE') {
    return const BusinessTypeLock.free();
  }
  final settings = tenant['settings'];
  if (settings is! Map) return const BusinessTypeLock.free();
  final layout = settings['businessLayout'];
  final stored = layout is Map ? layout['profileId']?.toString() : null;
  if (stored == null || stored.isEmpty) return const BusinessTypeLock.free();

  final approval = settings['approvedProfileChange'];
  final approvedId = approval is Map ? approval['profileId']?.toString() : null;
  final extras = approval is Map && approval['additionalProfileIds'] is List
      ? (approval['additionalProfileIds'] as List)
          .map((e) => e.toString())
          .toList()
      : <String>[];
  return BusinessTypeLock(
    locked: true,
    approvedProfileId: approvedId == null || approvedId.isEmpty ? null : approvedId,
    approvedAdditionalProfileIds: extras,
  );
}

final businessTypeLockProvider = Provider<BusinessTypeLock>((ref) {
  final user = ref.watch(currentUserProvider);
  return businessTypeLockFor(user,
      isLocalWorkspace: getIt<AuthService>().isLocalWorkspace);
});
