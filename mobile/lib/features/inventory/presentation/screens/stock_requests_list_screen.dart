import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/stock_request_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/di/injection.dart';

/// Stock Requests List Screen - For managers to view and approve stock requests
class StockRequestsListScreen extends ConsumerStatefulWidget {
  const StockRequestsListScreen({super.key});

  @override
  ConsumerState<StockRequestsListScreen> createState() =>
      _StockRequestsListScreenState();
}

class _StockRequestsListScreenState extends ConsumerState<StockRequestsListScreen>
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
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
      appBar: AppBar(
        title: const Text('Stock Requests'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Fulfilled'),
            Tab(text: 'All'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Show filter dialog
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRequestsList('PENDING'),
          _buildRequestsList('APPROVED'),
          _buildRequestsList('FULFILLED'),
          _buildRequestsList('ALL'),
        ],
      ),
    );
  }

  Widget _buildRequestsList(String status) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No ${status.toLowerCase()} requests',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final request = _requests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    // Extract request data
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Priority Badge
                  _buildPriorityBadge(priority),
                  const SizedBox(width: 12),

                  // Product Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (productSku.isNotEmpty)
                          Text(
                            'SKU: $productSku',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Status Badge
                  _buildStatusBadge(requestStatus),
                ],
              ),

              const SizedBox(height: 12),

              // Quantity & Stock Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Requested',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$quantity $unit',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey.shade300,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Stock',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$currentStock $unit',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: currentStock == 0
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Reason: $reason',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Footer Row
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      requesterName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.store_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    branchName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),

              // Action Buttons for Pending Requests
              if (requestStatus == 'PENDING') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectRequest(id),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _approveRequest(id),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],

              // Mark as Fulfilled button for Approved Requests
              if (requestStatus == 'APPROVED') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _fulfillRequest(id),
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Mark as Fulfilled'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color;
    IconData icon;

    switch (priority.toLowerCase()) {
      case 'urgent':
        color = Colors.red;
        icon = Icons.warning;
        break;
      case 'high':
        color = Colors.orange;
        icon = Icons.arrow_upward;
        break;
      case 'low':
        color = Colors.blue;
        icon = Icons.arrow_downward;
        break;
      default:
        color = Colors.grey;
        icon = Icons.remove;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            priority.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'PENDING':
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        break;
      case 'APPROVED':
        color = Colors.blue;
        icon = Icons.check_circle_outline;
        break;
      case 'FULFILLED':
        color = Colors.green;
        icon = Icons.done_all;
        break;
      case 'REJECTED':
        color = Colors.red;
        icon = Icons.cancel_outlined;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            status,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Request Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Product Info
                ListTile(
                  leading: const Icon(Icons.inventory_2),
                  title: Text(request['productName'] ?? ''),
                  subtitle: Text('SKU: ${request['productSku'] ?? ''}'),
                  contentPadding: EdgeInsets.zero,
                ),

                const Divider(),

                // Quantity
                ListTile(
                  leading: const Icon(Icons.numbers),
                  title: const Text('Requested Quantity'),
                  subtitle: Text('${request['quantity']} ${request['unit']}'),
                  contentPadding: EdgeInsets.zero,
                ),

                // Branch
                ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('Branch'),
                  subtitle: Text(request['branchName'] ?? ''),
                  contentPadding: EdgeInsets.zero,
                ),

                // Requester
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Requested By'),
                  subtitle: Text(request['requestedByName'] ?? ''),
                  contentPadding: EdgeInsets.zero,
                ),

                // Date
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Requested On'),
                  subtitle: Text(
                    DateFormat('MMM d, yyyy - hh:mm a').format(
                      request['createdAt'] as DateTime? ?? DateTime.now(),
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),

                if (request['reason'] != null && (request['reason'] as String).isNotEmpty) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.comment),
                    title: const Text('Reason'),
                    subtitle: Text(request['reason'] as String),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],

                // TODO: Display images if any
              ],
            ),
          );
        },
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request approved'),
          backgroundColor: Colors.green,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final reasonController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    
    if (result != true) return;
    
    try {
      final stockRequestService = ref.read(stockRequestServiceProvider);
      await stockRequestService.resolveRequest(
        requestId,
        approve: false,
        resolution: reasonController.text.trim().isEmpty 
            ? 'Rejected by manager' 
            : reasonController.text.trim(),
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request rejected'),
          backgroundColor: Colors.orange,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _fulfillRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Fulfilled'),
        content: const Text('Has this stock request been fulfilled?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final stockRequestService = ref.read(stockRequestServiceProvider);
      // For fulfilled status, we update the request
      // In the backend, you might need to add a separate endpoint or use update
      await stockRequestService.updateRequest(
        requestId,
        // Backend should handle status change to FULFILLED
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request marked as fulfilled'),
          backgroundColor: Colors.green,
        ),
      );
      _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
