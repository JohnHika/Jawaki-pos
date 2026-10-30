import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/design_system.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/auth_service.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

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
  ConsumerState<ProfitAdjustmentScreen> createState() =>
      _ProfitAdjustmentScreenState();
}

class _ProfitAdjustmentScreenState
    extends ConsumerState<ProfitAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _adjustmentController = TextEditingController();
  final _reasonController = TextEditingController();

  double _adjustedCost = 0;
  double _newProfit = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _adjustedCost = widget.currentCost;
    _newProfit = widget.currentRevenue - _adjustedCost;
    _adjustmentController.text = _adjustedCost.toStringAsFixed(0);
  }

  void _calculateProfit() {
    final adjustment = double.tryParse(_adjustmentController.text.trim());
    if (adjustment == null || !adjustment.isFinite || adjustment < 0) return;
    setState(() {
      _adjustedCost = adjustment;
      _newProfit = widget.currentRevenue - _adjustedCost;
    });
  }

  @override
  void dispose() {
    _adjustmentController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _saveAdjustment() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (!ref.read(permissionsProvider).canRecordRestock) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'You do not have permission to adjust purchase costs.',
          icon: Icons.lock_outline_rounded,
          color: DesignColors.warning,
        );
      }
      return;
    }

    final adjustedCost = double.parse(_adjustmentController.text.trim());
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

    setState(() {
      _saving = true;
      _adjustedCost = adjustedCost;
      _newProfit = widget.currentRevenue - adjustedCost;
    });
    try {
      final adjustmentAmount = adjustedCost - widget.currentCost;
      await getIt<AppDatabase>().setManualPurchaseAdjustment(
        branchId: branchId,
        amount: adjustmentAmount,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : null,
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
    } catch (_) {
      if (mounted) {
        showGlassSnackBar(
          context,
          'Could not save the profit adjustment. Your records were not changed.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A label with its amount on one line. The label wraps and the amount
  /// shrinks rather than overflowing on a narrow phone with large text.
  Widget _summaryRow(
    String label,
    String value, {
    required TextStyle labelStyle,
    required TextStyle valueStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, style: valueStyle, maxLines: 1),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'en_KE', symbol: 'KES ');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondaryColor =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final fieldFill = isDark ? DesignColors.darkSurfaceElevated : Colors.white;

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Adjust Profit',
        actions: [
          IconButton(
            tooltip: 'Help',
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
                        color: titleColor,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Adjust your cost of goods to match your accounting method',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: secondaryColor),
                ),
                const SizedBox(height: 20),

                // Current calculation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                  ),
                  child: Column(
                    children: [
                      _summaryRow(
                        'Current Sales:',
                        currencyFmt.format(widget.currentRevenue),
                        labelStyle: TextStyle(
                            fontWeight: FontWeight.w600, color: titleColor),
                        valueStyle: DesignType.numeric(color: titleColor),
                      ),
                      const SizedBox(height: 8),
                      _summaryRow(
                        'Auto-calculated Cost:',
                        currencyFmt.format(widget.currentCost),
                        labelStyle: TextStyle(
                            fontWeight: FontWeight.w600, color: titleColor),
                        valueStyle: DesignType.numeric(color: titleColor),
                      ),
                      const SizedBox(height: 8),
                      _summaryRow(
                        'Auto-calculated Profit:',
                        currencyFmt
                            .format(widget.currentRevenue - widget.currentCost),
                        labelStyle: TextStyle(
                            fontWeight: FontWeight.w600, color: titleColor),
                        valueStyle:
                            DesignType.numeric(fontSize: 14, color: titleColor),
                      ),
                      Divider(height: 24, color: border),
                      _summaryRow(
                        'Your Adjusted Cost:',
                        currencyFmt.format(_adjustedCost),
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: DesignColors.accent,
                        ),
                        valueStyle: DesignType.numeric(
                          fontSize: 15,
                          color: DesignColors.accent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _summaryRow(
                        'Your Adjusted Profit:',
                        currencyFmt.format(_newProfit),
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.readable(DesignColors.success),
                        ),
                        valueStyle: DesignType.numeric(
                          color: context.readable(DesignColors.success),
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Adjustment input
                Text(
                  'Set Your Cost of Goods',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adjustmentController,
                  style: DesignType.numeric(
                    color: titleColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Total cost of goods for today',
                    hintText: 'Enter your actual cost of goods',
                    prefixText: 'KES ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: fieldFill,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => _calculateProfit(),
                  validator: (value) {
                    final input = value?.trim() ?? '';
                    if (input.isEmpty) {
                      return 'Please enter cost of goods';
                    }
                    final amount = double.tryParse(input);
                    if (amount == null || !amount.isFinite) {
                      return 'Enter a valid cost amount';
                    }
                    if (amount < 0) return 'Cost cannot be negative';
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
                    hintText:
                        'e.g., Included additional expenses, different accounting method',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: fieldFill,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Save button
                GradientButton(
                  label: _saving ? 'Saving Adjustment' : 'Save Adjustment',
                  icon: Icons.save_rounded,
                  onPressed: _saving ? null : _saveAdjustment,
                  isLoading: _saving,
                  height: 52,
                  borderRadius: 12,
                ),
                const SizedBox(height: 16),

                // Info about simple calculation
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DesignColors.info.withValues(alpha: 0.06),
                    border: Border.all(
                        color: DesignColors.info.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: context.readable(DesignColors.info),
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Simple Profit Formula',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.readable(DesignColors.info),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: secondaryColor),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: titleColor,
                                  )),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),
              Text(
                'Your adjustment will be saved and used for all profit reports today.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: secondaryColor,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
