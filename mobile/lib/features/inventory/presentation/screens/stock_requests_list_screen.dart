import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/stock_request_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/theme/design_system.dart';

/// Stock Requests List Screen - For managers to view and approve stock requests
class StockRequestsListScreen extends ConsumerStatefulWidget {
  const StockRequestsListScreen({super.key});

  @override
  ConsumerState<StockRequestsListScreen> createState() =>
      _StockRequestsListScreenState();
}

class _StockRequestsListScreenState
    extends ConsumerState<StockRequestsListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedStatus = 'PENDING';
  bool _isLoading = false;
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          switch (_tabController.index) {
            case 0:
              _selectedStatus = 'PENDING';
              break;
            case 1:
              _selectedStatus = 'APPROVED';
              break;
            case 2:
              _selectedStatus = 'FULFILLED';
              break;
            case 3:
              _selectedStatus = 'ALL';
              break;
          }
        });
        _loadRequests();
      }
    });

    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final authService = getIt<AuthService>();
      final stockRequestService = ref.read(stockRequestServiceProvider);

      final branchId = authService.branchId;
      final requests = await stockRequestService.getRequests(
        branchId: branchId,
        status: _selectedStatus == 'ALL' ? null : _selectedStatus,
      );

      if (mounted) {
        setState(() => _requests = requests);
      }
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Error loading requests',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Stock Requests',
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.surfaceBorder.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.filter_list_rounded,
                  color: DesignColors.textSecondary, size: 20),
            ),
            onPressed: () {
              // TODO: Show filter dialog
            },
          ),
        ],
      ),
      body: PageContainer(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Premium Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: DesignColors.surfaceBorder.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: DesignColors.textOnBrand,
                unselectedLabelColor: DesignColors.textSecondary,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [DesignColors.brand, DesignColors.brandDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicatorPadding: const EdgeInsets.all(4),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'Pending'),
                  Tab(text: 'Approved'),
                  Tab(text: 'Fulfilled'),
                  Tab(text: 'All'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRequestsList('PENDING'),
                  _buildRequestsList('APPROVED'),
                  _buildRequestsList('FULFILLED'),
                  _buildRequestsList('ALL'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsList(String status) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: DesignColors.brand),
      );
    }

    if (_requests.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No ${status.toLowerCase()} requests',
        subtitle: 'All caught up! No requests to review.',
        iconColor: DesignColors.textTertiary,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: DesignColors.brand,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final id = request['id'] as String;
    final productName = request['productName'] as String? ?? 'Unknown Product';
    final productSku = request['productSku'] as String? ?? '';
    final quantity = request['quantity'] as num? ?? 0;
    final unit = request['unit'] as String? ?? 'piece';
    final priority = request['priority'] as String? ?? 'normal';
    final requestStatus = request['status'] as String? ?? 'PENDING';
    final requesterName = request['requestedByName'] as String? ?? 'Unknown';
    final branchName = request['branchName'] as String? ?? 'Unknown Branch';
    final reason = request['reason'] as String?;
    final createdAt = request['createdAt'] as DateTime? ?? DateTime.now();
    final currentStock = request['currentStock'] as num? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        onTap: () => _showRequestDetails(request),
        padding: const EdgeInsets.all(16),
        borderRadius: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Priority Badge
                _buildPriorityBadge(priority),
                const SizedBox(width: 10),

                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DesignColors.textPrimary,
                        ),
                      ),
                      if (productSku.isNotEmpty)
                        Text(
                          'SKU: $productSku',
                          style: const TextStyle(
                            fontSize: 11,
                            color: DesignColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),

                // Status Badge
                _buildStatusBadge(requestStatus),
              ],
            ),

            const SizedBox(height: 14),

            // Quantity & Stock Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DesignColors.surfaceBorder.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Requested',
                          style: TextStyle(
                            fontSize: 11,
                            color: DesignColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$quantity $unit',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: DesignColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 44,
                    color: DesignColors.surfaceBorder,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Stock',
                          style: TextStyle(
                            fontSize: 11,
                            color: DesignColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$currentStock $unit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: currentStock == 0
                                ? DesignColors.error
                                : currentStock < quantity
                                    ? DesignColors.warning
                                    : DesignColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                reason,
                style: TextStyle(
                  fontSize: 13,
                  color: DesignColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Footer Row
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 14, color: DesignColors.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    requesterName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DesignColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.store_outlined,
                    size: 14, color: DesignColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  branchName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DesignColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded,
                    size: 14, color: DesignColors.textTertiary),
                const SizedBox(width: 4),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: DesignColors.textTertiary,
                  ),
                ),
              ],
            ),

            // Action Buttons for Pending Requests
            if (requestStatus == 'PENDING') ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectRequest(id),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DesignColors.error,
                        side: const BorderSide(color: DesignColors.error),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'Approve',
                      icon: Icons.check_rounded,
                      onPressed: () => _approveRequest(id),
                      gradient: [
                        DesignColors.success,
                        const Color(0xFF059669),
                      ],
                      height: 44,
                      borderRadius: 12,
                    ),
                  ),
                ],
              ),
            ],

            // Mark as Fulfilled button for Approved Requests
            if (requestStatus == 'APPROVED') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Mark as Fulfilled',
                  icon: Icons.done_all_rounded,
                  onPressed: () => _fulfillRequest(id),
                  gradient: [
                    Colors.teal,
                    const Color(0xFF0F766E),
                  ],
                  height: 44,
                  borderRadius: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color;
    IconData icon;

    switch (priority.toLowerCase()) {
      case 'urgent':
        color = DesignColors.error;
        icon = Icons.warning_rounded;
        break;
      case 'high':
        color = DesignColors.warning;
        icon = Icons.arrow_upward_rounded;
        break;
      case 'low':
        color = DesignColors.info;
        icon = Icons.arrow_downward_rounded;
        break;
      default:
        color = DesignColors.textTertiary;
        icon = Icons.remove_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            priority.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    IconData? icon;

    switch (status) {
      case 'PENDING':
        color = DesignColors.warning;
        icon = Icons.hourglass_empty_rounded;
        break;
      case 'APPROVED':
        color = DesignColors.info;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'FULFILLED':
        color = DesignColors.success;
        icon = Icons.done_all_rounded;
        break;
      case 'REJECTED':
        color = DesignColors.error;
        icon = Icons.cancel_outlined;
        break;
      default:
        color = DesignColors.textTertiary;
        icon = Icons.help_outline_rounded;
    }

    return StatusBadge(
      label: status,
      color: color,
      icon: icon,
      isActive: true,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    return DateFormat('MMM d').format(date);
  }

  Future<void> _showRequestDetails(Map<String, dynamic> request) async {
    GlassBottomSheet.show(
      context,
      initialSize: 0.6,
      maxSize: 0.9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Request Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: DesignColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DesignColors.surfaceBorder.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Product Info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: DesignColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_rounded,
                      color: DesignColors.brand, size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['productName'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: DesignColors.textPrimary,
                      ),
                    ),
                    Text(
                      'SKU: ${request['productSku'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DesignColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),
            const LabelDivider(label: 'DETAILS'),

            _detailRow(
              Icons.numbers_rounded,
              'Requested Quantity',
              '${request['quantity']} ${request['unit']}',
            ),
            const SizedBox(height: 10),
            _detailRow(
              Icons.store_rounded,
              'Branch',
              request['branchName'] ?? '',
            ),
            const SizedBox(height: 10),
            _detailRow(
              Icons.person_rounded,
              'Requested By',
              request['requestedByName'] ?? '',
            ),
            const SizedBox(height: 10),
            _detailRow(
              Icons.calendar_today_rounded,
              'Requested On',
              DateFormat('MMM d, yyyy - hh:mm a').format(
                request['createdAt'] as DateTime? ?? DateTime.now(),
              ),
            ),

            if (request['reason'] != null &&
                (request['reason'] as String).isNotEmpty) ...[
              const SizedBox(height: 16),
              const LabelDivider(label: 'REASON'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DesignColors.surfaceBorder.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  request['reason'] as String,
                  style: const TextStyle(
                    fontSize: 14,
                    color: DesignColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: DesignColors.surfaceBorder.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: DesignColors.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: DesignColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DesignColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      final stockRequestService = ref.read(stockRequestServiceProvider);
      await stockRequestService.resolveRequest(
        requestId,
        approve: true,
        resolution: 'Approved by manager',
      );

      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Request approved',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Error: ${e.toString()}',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final reasonController = TextEditingController();

    final confirmed = await showConfirmDialog(
      context,
      title: 'Reject Request',
      message: 'Are you sure you want to reject this stock request?',
      confirmLabel: 'Reject',
      confirmColor: DesignColors.error,
    );

    if (confirmed != true) {
      reasonController.dispose();
      return;
    }

    try {
      final stockRequestService = ref.read(stockRequestServiceProvider);
      await stockRequestService.resolveRequest(
        requestId,
        approve: false,
        resolution: 'Rejected by manager',
      );

      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Request rejected',
        icon: Icons.cancel_outlined,
        color: DesignColors.warning,
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Error: ${e.toString()}',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _fulfillRequest(String requestId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark as Fulfilled',
      message: 'Has this stock request been fulfilled?',
      confirmLabel: 'Confirm',
      confirmColor: DesignColors.success,
    );

    if (confirmed != true) return;

    try {
      final stockRequestService = ref.read(stockRequestServiceProvider);
      await stockRequestService.updateRequest(
        requestId,
      );

      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Request marked as fulfilled',
        icon: Icons.done_all_rounded,
        color: DesignColors.success,
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(
        context,
        'Error: ${e.toString()}',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }
}
