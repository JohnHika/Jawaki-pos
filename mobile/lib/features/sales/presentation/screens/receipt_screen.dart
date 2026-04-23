import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/sales_provider.dart';

class ReceiptScreen extends ConsumerWidget {
  final String saleId;

  const ReceiptScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptProvider(saleId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              // Share receipt
            },
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: () {
              // Print receipt
            },
          ),
        ],
      ),
      body: receiptAsync.when(
        data: (receipt) => _buildReceipt(context, receipt),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Failed to load receipt: $e'),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.refresh(receiptProvider(saleId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('New Sale'),
          ),
        ),
      ),
    );
  }

  Widget _buildReceipt(BuildContext context, Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Success Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'Payment Successful',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            
            // Store Info
            Text(
              receipt['branchName'] ?? 'POS Store',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              receipt['branchAddress'] ?? '',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            
            // Customer Info (if available)
            if (receipt['customerName'] != null || receipt['customerPhone'] != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Customer',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  Text(
                    receipt['customerName'] ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (receipt['customerPhone'] != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Phone',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      receipt['customerPhone'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(),
              ),
            ],

            // Date & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Date',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                Text(
                  _formatDateTime(receipt['createdAt']),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cashier',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                Text(
                  receipt['cashierName'] ?? 'N/A',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Divider(),
            ),
            
            // Items
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['productName'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${item['quantity']} x KES ${(item['unitPrice'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'KES ${(item['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            
            // Totals
            _buildTotalRow('Subtotal', receipt['subtotal']),
            const SizedBox(height: 4),
            if ((receipt['discount'] as num?) != null && (receipt['discount'] as num) > 0)
              _buildTotalRow('Discount', receipt['discount'], isDiscount: true),
            _buildTotalRow('Tax', receipt['tax']),
            const SizedBox(height: 8),
            _buildTotalRow(
              'Total',
              receipt['total'],
              isBold: true,
              isPrimary: true,
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(),
            ),
            
            // Payment Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Method',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPaymentMethodColor(receipt['paymentMethod']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    receipt['paymentMethod'] ?? 'CASH',
                    style: TextStyle(
                      color: _getPaymentMethodColor(receipt['paymentMethod']),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Thank you message
            Text(
              'Thank you for your purchase!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    dynamic amount, {
    bool isBold = false,
    bool isPrimary = false,
    bool isDiscount = false,
  }) {
    final amountValue = (amount as num?)?.toDouble() ?? 0.0;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          '${isDiscount ? '- ' : ''}KES ${amountValue.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: isBold ? 18 : 14,
            color: isDiscount 
                ? AppColors.success 
                : isPrimary 
                    ? AppColors.primary 
                    : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    final dt = dateTime is DateTime ? dateTime : DateTime.parse(dateTime.toString());
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _getPaymentMethodColor(String? method) {
    switch (method?.toUpperCase()) {
      case 'MPESA':
        return AppColors.mpesa;
      case 'PESAPAL':
        return AppColors.pesapal;
      case 'TOURISTTAP':
        return AppColors.touristtap;
      default:
        return AppColors.cash;
    }
  }
}
