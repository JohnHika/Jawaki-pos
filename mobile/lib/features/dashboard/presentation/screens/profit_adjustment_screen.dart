import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/auth_service.dart';

class ProfitAdjustmentScreen extends ConsumerStatefulWidget {
  final DateTime date;
  final double currentRevenue;
  final double currentCost;

  const ProfitAdjustmentScreen({
    super.key,
    required this.date,
    required this.currentRevenue,
    required this.currentCost,
  });

  @override
  ConsumerState<ProfitAdjustmentScreen> createState() => _ProfitAdjustmentScreenState();
}

class _ProfitAdjustmentScreenState extends ConsumerState<ProfitAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _adjustmentController = TextEditingController();
  final _reasonController = TextEditingController();

  double _adjustedCost = 0;
  double _newProfit = 0;

  @override
  void initState() {
    super.initState();
    _adjustedCost = widget.currentCost;
    _newProfit = widget.currentRevenue - _adjustedCost;
    _adjustmentController.text = _adjustedCost.toStringAsFixed(0);
  }

  void _calculateProfit() {
    final adjustment = double.tryParse(_adjustmentController.text) ?? 0;
    setState(() {
      _adjustedCost = adjustment;
      _newProfit = widget.currentRevenue - _adjustedCost;
    });
  }

  Future<void> _saveAdjustment() async {
    if (!_formKey.currentState!.validate()) return;

    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'No branch selected. Please log in again.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
      return;
    }

    final db = getIt<AppDatabase>();
    final adjustmentAmount = _adjustedCost - widget.currentCost;

    await db.setManualPurchaseAdjustment(
      branchId: branchId,
      amount: adjustmentAmount,
      reason: _reasonController.text.isNotEmpty ? _reasonController.text : null,
    );

    if (mounted) {
      showGlassSnackBar(
        context,
        'Profit adjustment saved successfully!',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ');

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Adjust Profit Calculation',
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: PageContainer(
        withScroll: true,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Profit Adjustment',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Adjust your cost of goods to match your accounting method',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DesignColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // Current calculation
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 12,
                  blur: 8,
                  tint: DesignColors.brand.withValues(alpha: 0.05),
                  borderColor: DesignColors.brand.withValues(alpha: 0.1),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Current Sales:', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(currencyFmt.format(widget.currentRevenue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Auto-calculated Cost:', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(currencyFmt.format(widget.currentCost)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Auto-calculated Profit:', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(currencyFmt.format(widget.currentRevenue - widget.currentCost)),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Your Adjusted Cost:', style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.brand,
                          )),
                          Text(currencyFmt.format(_adjustedCost), style: TextStyle(
                            color: DesignColors.brand,
                            fontWeight: FontWeight.bold,
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Your Adjusted Profit:', style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.success,
                          )),
                          Text(currencyFmt.format(_newProfit), style: TextStyle(
                            color: DesignColors.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Adjustment input
                Text(
                  'Set Your Cost of Goods',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adjustmentController,
                  decoration: InputDecoration(
                    labelText: 'Total cost of goods for today',
                    hintText: 'Enter your actual cost of goods',
                    prefixText: 'KES ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.1),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _calculateProfit(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter cost of goods';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Reason (optional)
                TextFormField(
                  controller: _reasonController,
                  decoration: InputDecoration(
                    labelText: 'Reason for adjustment (optional)',
                    hintText: 'e.g., Included additional expenses, different accounting method',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: DesignColors.surfaceBorder.withValues(alpha: 0.1),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Save button
                GradientButton(
                  label: 'Save Adjustment',
                  icon: Icons.save_rounded,
                  onPressed: _saveAdjustment,
                  height: 52,
                  borderRadius: 12,
                  gradient: [DesignColors.brand, DesignColors.brandDark],
                ),
                const SizedBox(height: 16),

                // Info about simple calculation
                GlassCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: 12,
                  tint: DesignColors.info.withValues(alpha: 0.05),
                  borderColor: DesignColors.info.withValues(alpha: 0.1),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: DesignColors.info, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Simple Profit Formula',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: DesignColors.info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              'Profit = Today\'s Sales - Today\'s Cost of Goods',
                              style: TextStyle(color: DesignColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              'No complex calculations - just clean, simple math!',
                              style: TextStyle(color: DesignColors.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    GlassBottomSheet.show(
      context,
      title: 'Profit Adjustment Help',
      initialSize: 0.5,
      maxSize: 0.7,
      scrollable: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Use this screen to adjust your profit calculation when:',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: DesignColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ...[
              'You use a different accounting method',
              'You have additional expenses to include',
              'You want to match your existing bookkeeping',
              'The auto-calculation doesn\'t match your records',
            ].map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 16, color: DesignColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 14, color: DesignColors.textPrimary)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            const Text(
              'Your adjustment will be saved and used for all profit reports today.',
              style: TextStyle(fontSize: 12, color: DesignColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
