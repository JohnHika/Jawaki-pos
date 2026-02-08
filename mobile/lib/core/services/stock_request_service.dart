import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../providers/api_provider.dart';

class StockRequestService {
  final ApiClient _apiClient;

  StockRequestService(this._apiClient);

  /// Create a new stock request
  Future<Map<String, dynamic>> createRequest({
    required String branchId,
    required String productId,
    required double quantity,
    String? unit,
    String? reason,
    String? priority,
    List<String>? images,
  }) async {
    try {
      final data = {
        'branchId': branchId,
        'productId': productId,
        'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (reason != null) 'reason': reason,
        if (priority != null) 'priority': priority,
        if (images != null && images.isNotEmpty) 'images': images,
      };

      final response = await _apiClient.createStockRequest(data);
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Get all stock requests with optional filtering
  Future<List<dynamic>> getRequests({
    String? branchId,
    String? status,
    String? priority,
    int? page,
    int? limit,
  }) async {
    try {
      final requests = await _apiClient.getStockRequests(
        branchId: branchId,
        status: status,
        priority: priority,
        page: page,
        limit: limit,
      );
      return requests;
    } catch (e) {
      rethrow;
    }
  }

  /// Get a single stock request by ID
  Future<Map<String, dynamic>> getRequest(String id) async {
    try {
      final request = await _apiClient.getStockRequest(id);
      return request;
    } catch (e) {
      rethrow;
    }
  }

  /// Update a stock request (only allowed for PENDING requests)
  Future<Map<String, dynamic>> updateRequest(
    String id, {
    double? quantity,
    String? unit,
    String? reason,
    String? priority,
  }) async {
    try {
      final data = {
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (reason != null) 'reason': reason,
        if (priority != null) 'priority': priority,
      };

      final response = await _apiClient.updateStockRequest(id, data);
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Approve or reject a stock request (Supervisor/Manager only)
  Future<Map<String, dynamic>> resolveRequest(
    String id, {
    required bool approve,
    String? resolution,
  }) async {
    try {
      final data = {
        'approve': approve,
        if (resolution != null) 'resolution': resolution,
      };

      final response = await _apiClient.resolveStockRequest(id, data);
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Cancel a stock request
  Future<Map<String, dynamic>> cancelRequest(
    String id, {
    String? reason,
  }) async {
    try {
      final data = {
        if (reason != null) 'reason': reason,
      };

      final response = await _apiClient.cancelStockRequest(id, data);
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Get stock request statistics (Manager+ only)
  Future<Map<String, dynamic>> getStats({String? branchId}) async {
    try {
      final stats = await _apiClient.getStockRequestStats(branchId: branchId);
      return stats;
    } catch (e) {
      rethrow;
    }
  }

  /// Helper method to get pending requests count
  Future<int> getPendingCount({String? branchId}) async {
    try {
      final requests = await getRequests(
        branchId: branchId,
        status: 'PENDING',
        limit: 1,
      );
      // In a real scenario, the API should return total count
      // For now, we'll use the length of the returned array
      return requests.length;
    } catch (e) {
      return 0;
    }
  }

  /// Helper method to get requests by status
  Future<List<dynamic>> getRequestsByStatus(
    String status, {
    String? branchId,
  }) async {
    return getRequests(
      branchId: branchId,
      status: status,
    );
  }
}

// Riverpod provider for StockRequestService
final stockRequestServiceProvider = Provider<StockRequestService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return StockRequestService(apiClient);
});
