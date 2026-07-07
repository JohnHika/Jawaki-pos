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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final fieldFill = isDark
        ? DesignColors.darkSurfaceElevated
        : DesignColors.surfaceSubtle;

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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Adjust your cost of goods to match your accounting method',
                  style: TextStyle(fontSize: 14, color: secondaryColor),
                ),
                const SizedBox(height: 20),

                // Current calculation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration:
                      BoxDecoration(color: surface, border: Border.all(color: border)),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Current Sales:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: titleColor)),
                          Text(currencyFmt.format(widget.currentRevenue),
                              style: DesignType.numeric(
                                  fontSize: 14, color: titleColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Auto-calculated Cost:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: titleColor)),
                          Text(currencyFmt.format(widget.currentCost),
                              style: DesignType.numeric(
                                  fontSize: 14, color: titleColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Auto-calculated Profit:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, color: titleColor)),
                          Text(
                              currencyFmt.format(
                                  widget.currentRevenue - widget.currentCost),
                              style: DesignType.numeric(
                                  fontSize: 14, color: titleColor)),
                        ],
                      ),
                      Divider(height: 24, color: border),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Your Adjusted Cost:', style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.accent,
                          )),
                          Text(currencyFmt.format(_adjustedCost),
                              style: DesignType.numeric(
                            fontSize: 15,
                            color: DesignColors.accent,
                          )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Your Adjusted Profit:', style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: DesignColors.success,
                          )),
                          Text(currencyFmt.format(_newProfit),
                              style: DesignType.numeric(
                            color: DesignColors.success,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adjustmentController,
                  style: TextStyle(color: titleColor),
                  decoration: InputDecoration(
                    labelText: 'Total cost of goods for today',
                    hintText: 'Enter your actual cost of goods',
                    prefixText: 'KES ',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: fieldFill,
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
                  style: TextStyle(color: titleColor),
                  decoration: InputDecoration(
                    labelText: 'Reason for adjustment (optional)',
                    hintText: 'e.g., Included additional expenses, different accounting method',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: fieldFill,
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
                ),
                const SizedBox(height: 16),

                // Info about simple calculation
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DesignColors.info.withValues(alpha: 0.06),
                    border: Border.all(color: DesignColors.info.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: DesignColors.info, size: 20),
                          const SizedBox(width: 8),
                          const Text(
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
                              style: TextStyle(color: secondaryColor),
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
                              style: TextStyle(color: secondaryColor, fontSize: 12),
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
      child: Builder(builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final titleColor =
            isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
        final secondaryColor = isDark
            ? DesignColors.darkTextSecondary
            : DesignColors.textSecondary;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use this screen to adjust your profit calculation when:',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
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
                          style: TextStyle(fontSize: 14, color: titleColor)),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              Text(
                'Your adjustment will be saved and used for all profit reports today.',
                style: TextStyle(fontSize: 12, color: secondaryColor),
              ),
            ],
          ),
        );
      }),
    );
  }
}
