import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../providers/sales_provider.dart';

class ReceiptScreen extends ConsumerWidget {
  final String saleId;

  const ReceiptScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptProvider(saleId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkSurfaceElevated
                    : DesignColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded, size: 20),
            ),
            onPressed: () => context.go('/'),
          ),
        ),
        title: Text(
          'Receipt',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: -0.5,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.share_outlined, size: 20, color: DesignColors.brand),
            ),
            tooltip: 'Share receipt',
            onPressed: () {
              final receipt = receiptAsync.valueOrNull;
              if (receipt == null) {
                showGlassSnackBar(
                  context,
                  'Receipt is still loading — try again in a moment.',
                  icon: Icons.hourglass_empty_rounded,
                  color: DesignColors.warning,
                );
                return;
              }
              Share.share(_buildShareText(receipt));
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.print_outlined,
                  size: 20, color: DesignColors.brand),
            ),
            tooltip: 'Set up a receipt printer',
            onPressed: () {
              showGlassSnackBar(
                context,
                'Set up a receipt printer in Settings to print receipts.',
                icon: Icons.print_outlined,
                color: DesignColors.info,
                actionLabel: 'Open Settings',
                onAction: () => context.push('/settings'),
              );
            },
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DesignColors.error.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.block_rounded,
                  size: 20, color: DesignColors.error),
            ),
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Void Sale',
                message: 'Are you sure you want to void this sale? This cannot be undone.',
                confirmLabel: 'Void Sale',
                cancelLabel: 'Keep Sale',
                confirmColor: DesignColors.error,
              );
              if (!confirmed) return;

              try {
                final db = getIt<AppDatabase>();
                await db.customStatement(
                  'DELETE FROM pending_sales WHERE id = ?',
                  [Variable.withString(saleId)],
                );
                await db.customStatement(
                  'DELETE FROM pending_sale_items WHERE sale_id = ?',
                  [Variable.withString(saleId)],
                );

                if (context.mounted) {
                  showGlassSnackBar(
                    context,
                    'Sale voided successfully',
                    icon: Icons.check_circle_outline_rounded,
                    color: DesignColors.success,
                  );
                  context.go('/');
                }
              } catch (e) {
                if (context.mounted) {
                  showGlassSnackBar(
                    context,
                    'Failed to void sale: $e',
                    icon: Icons.error_outline_rounded,
                    color: DesignColors.error,
                  );
                }
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      backgroundColor: isDark ? DesignColors.darkBg : DesignColors.surfaceMuted,
      body: receiptAsync.when(
        data: (receipt) => _buildReceipt(context, receipt),
        loading: () => const Center(
          child: CircularProgressIndicator(color: DesignColors.brand),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Failed to load receipt',
          subtitle: e.toString(),
          actionLabel: 'Retry',
          iconColor: DesignColors.error,
          onAction: () => ref.refresh(receiptProvider(saleId)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GradientButton(
            label: 'New Sale',
            icon: Icons.add_shopping_cart_rounded,
            onPressed: () => context.go('/'),
            height: 56,
            borderRadius: 16,
            gradient: const [DesignColors.brand, DesignColors.brandDark],
          ),
        ),
      ),
    );
  }

  Widget _buildReceipt(BuildContext context, Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        borderRadius: 20,
        blur: 12,
        tint: isDark
            ? DesignColors.darkSurfaceElevated.withValues(alpha:0.95)
            : Colors.white.withValues(alpha:0.95),
        borderColor:
            isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Success Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: DesignColors.success.withValues(alpha:0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: DesignColors.success.withValues(alpha:0.2), width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: DesignColors.success,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Payment Successful',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: DesignColors.success,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),

            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? DesignColors.darkTextSecondary
                      : DesignColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 20),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                    DesignColors.surfaceBorder,
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Store Info
            Text(
              receipt['branchName'] ?? 'POS Store',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              receipt['branchAddress'] ?? '',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? DesignColors.darkTextSecondary
                    : DesignColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Customer Info (if available)
            if (receipt['customerName'] != null ||
                receipt['customerPhone'] != null) ...[
              GlassCard(
                padding: const EdgeInsets.all(12),
                borderRadius: 12,
                blur: 4,
                tint: Colors.teal.withValues(alpha:0.04),
                borderColor: Colors.teal.withValues(alpha:0.12),
                child: Column(
                  children: [
                    _buildReceiptRow(context,
                        'Customer', receipt['customerName'] ?? 'N/A'),
                    if (receipt['customerPhone'] != null) ...[
                      const SizedBox(height: 6),
                      _buildReceiptRow(context,
                          'Phone', receipt['customerPhone'] ?? ''),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Date & Time
            GlassCard(
              padding: const EdgeInsets.all(12),
              borderRadius: 12,
              blur: 4,
              tint: isDark ? DesignColors.glassDark : DesignColors.glassWhite,
              borderColor: isDark
                  ? DesignColors.glassDarkBorder
                  : DesignColors.glassBorder,
              child: Column(
                children: [
                  _buildReceiptRow(context, 'Date',
                      _formatDateTime(receipt['createdAt'])),
                  const SizedBox(height: 6),
                  _buildReceiptRow(context,
                      'Cashier', receipt['cashierName'] ?? 'N/A'),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                    DesignColors.surfaceBorder,
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Items header
            Row(
              children: [
                Text(
                  'Items',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length} item${items.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? DesignColors.darkTextTertiary
                        : DesignColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Items
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: index < items.length - 1 ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: DesignColors.brand.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${item['quantity']}x',
                          style: const TextStyle(
                            color: DesignColors.brand,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['productName'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isDark
                                  ? DesignColors.darkTextPrimary
                                  : DesignColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item['quantity']} x KES ${(item['unitPrice'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? DesignColors.darkTextTertiary
                                  : DesignColors.textTertiary,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isDark
                              ? DesignColors.darkTextPrimary
                              : DesignColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                    DesignColors.surfaceBorder,
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Totals
            _buildTotalRow(context, 'Subtotal', receipt['subtotal']),
            const SizedBox(height: 6),
            if ((receipt['discount'] as num?) != null &&
                (receipt['discount'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildTotalRow(context, 'Discount', receipt['discount'],
                    isDiscount: true),
              ),
            if (getIt<AuthService>().showTaxOnReceipt &&
                (receipt['tax'] as num?) != null &&
                (receipt['tax'] as num) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildTotalRow(context, 'Tax', receipt['tax']),
              ),
            const SizedBox(height: 12),
            Container(
              height: 1,
              decoration: BoxDecoration(
                color: isDark
                    ? DesignColors.darkBorder
                    : DesignColors.surfaceBorder,
              ),
            ),
            const SizedBox(height: 12),
            _buildTotalRow(context,
              'Total',
              receipt['total'],
              isBold: true,
              isPrimary: true,
            ),

            const SizedBox(height: 20),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                    DesignColors.surfaceBorder,
                    DesignColors.surfaceBorder.withValues(alpha:0.1),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Payment Method',
                  style: TextStyle(
                    color: isDark
                        ? DesignColors.darkTextSecondary
                        : DesignColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                PaymentChip(
                  method: receipt['paymentMethod'] ?? 'CASH',
                  isSelected: true,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Thank you message
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DesignColors.brand.withValues(alpha:0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: DesignColors.brand.withValues(alpha:0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_rounded,
                      size: 16, color: DesignColors.error),
                  const SizedBox(width: 8),
                  Text(
                    'Thank you for your purchase!',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? DesignColors.darkTextPrimary
                          : DesignColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isDark
                ? DesignColors.darkTextPrimary
                : DesignColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(BuildContext context,
    String label,
    dynamic amount, {
    bool isBold = false,
    bool isPrimary = false,
    bool isDiscount = false,
  }) {
    final amountValue = (amount as num?)?.toDouble() ?? 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            fontSize: isBold ? 16 : 14,
            color: isDark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary,
          ),
        ),
        Text(
          '${isDiscount ? '- ' : ''}KES ${amountValue.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            fontSize: isBold ? 20 : 14,
            letterSpacing: isBold ? -0.3 : 0,
            color: isDiscount
                ? DesignColors.success
                : isPrimary
                    ? DesignColors.brand
                    : (isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    final dt =
        dateTime is DateTime ? dateTime : DateTime.parse(dateTime.toString());
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _buildShareText(Map<String, dynamic> receipt) {
    final items = receipt['items'] as List? ?? [];
    final buffer = StringBuffer();

    buffer.writeln(receipt['branchName'] ?? 'POS Store');
    if ((receipt['branchAddress'] as String?)?.isNotEmpty == true) {
      buffer.writeln(receipt['branchAddress']);
    }
    buffer.writeln('Receipt #${receipt['receiptNumber'] ?? saleId.substring(0, 8).toUpperCase()}');
    buffer.writeln(_formatDateTime(receipt['createdAt']));
    buffer.writeln('---');

    for (final item in items) {
      final name = item['productName'] ?? '';
      final qty = item['quantity'];
      final total = (item['total'] as num?)?.toStringAsFixed(2) ?? '0.00';
      buffer.writeln('$qty x $name — KES $total');
    }

    buffer.writeln('---');
    buffer.writeln('Subtotal: KES ${((receipt['subtotal'] as num?) ?? 0).toStringAsFixed(2)}');
    final discount = (receipt['discount'] as num?) ?? 0;
    if (discount > 0) {
      buffer.writeln('Discount: -KES ${discount.toStringAsFixed(2)}');
    }
    final tax = (receipt['tax'] as num?) ?? 0;
    if (getIt<AuthService>().showTaxOnReceipt && tax > 0) {
      buffer.writeln('Tax: KES ${tax.toStringAsFixed(2)}');
    }
    buffer.writeln('Total: KES ${((receipt['total'] as num?) ?? 0).toStringAsFixed(2)}');
    buffer.writeln('Payment: ${receipt['paymentMethod'] ?? 'CASH'}');
    buffer.writeln();
    buffer.writeln('Thank you for your purchase!');

    return buffer.toString();
  }
}
