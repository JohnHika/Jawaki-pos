import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

final customerCreditProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, customerId) async {
  return getIt<ApiClient>().getCustomerCredit(customerId);
});

/// How much a customer may owe, how much they owe now, and what is left.
/// Only a manager (who may override credit) can change the limit.
class CreditLimitCard extends ConsumerWidget {
  const CreditLimitCard({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final String customerId;
  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ref.watch(customerCreditProvider(customerId));
    final canEdit = ref.watch(permissionsProvider).has('sales.credit_override');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? DesignColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
        border: Border.all(
            color: isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder),
      ),
      child: standing.when(
        loading: () => const SizedBox(
          height: 56,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: secondary),
            const SizedBox(width: DesignSpacing.sm),
            Expanded(
              child: Text('Credit details need a connection.',
                  style: TextStyle(color: secondary)),
            ),
            TextButton(
              onPressed: () => ref.invalidate(customerCreditProvider(customerId)),
              child: const Text('Retry'),
            ),
          ],
        ),
        data: (s) {
          if (s['known'] == false) {
            return Text(
              'This customer has not reached the server yet. Credit limits can be set once they sync.',
              style: TextStyle(color: secondary),
            );
          }
          final limit = s['limit'] == null ? null : asDouble(s['limit']);
          final owes = asDouble(s['outstanding']);
          final available =
              s['available'] == null ? null : asDouble(s['available']);
          final overdueDays = asInt(s['oldestOverdueDays']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.credit_score_rounded,
                      color: DesignColors.accent, size: 20),
                  const SizedBox(width: DesignSpacing.sm),
                  const Expanded(
                    child: Text('Credit',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  if (canEdit)
                    TextButton(
                      onPressed: () => _edit(context, ref, limit),
                      child: const Text('Set limit'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                limit == null
                    ? 'No limit set'
                    : 'Limit ${kesWhole(limit)}${s['limitIsDefault'] == true ? ' (shop default)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                'Owes ${kesWhole(owes)}'
                '${available != null ? ' · ${kesWhole(available)} left' : ''}',
                style: TextStyle(color: secondary),
              ),
              if (overdueDays > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Oldest unpaid balance is $overdueDays day${overdueDays == 1 ? '' : 's'} past due',
                    style: const TextStyle(
                        color: DesignColors.error, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, double? current) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LimitSheet(name: customerName, current: current),
    );
    if (result == null || !context.mounted) return;
    try {
      await getIt<ApiClient>().updateCustomer(customerId, result);
      ref.invalidate(customerCreditProvider(customerId));
      if (context.mounted) {
        showGlassSnackBar(context, 'Credit limit saved',
            icon: Icons.check_circle_rounded, color: DesignColors.success);
      }
    } catch (e) {
      if (context.mounted) {
        showGlassSnackBar(context, apiErrorMessage(e),
            icon: Icons.error_outline_rounded, color: DesignColors.error);
      }
    }
  }
}

class _LimitSheet extends StatefulWidget {
  const _LimitSheet({required this.name, required this.current});

  final String name;
  final double? current;

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  late final TextEditingController _limit = TextEditingController(
      text: widget.current == null ? '' : kitNumber(widget.current!));
  final _idNumber = TextEditingController();
  final _guarantor = TextEditingController();
  final _guarantorPhone = TextEditingController();

  @override
  void dispose() {
    _limit.dispose();
    _idNumber.dispose();
    _guarantor.dispose();
    _guarantorPhone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Credit for ${widget.name}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _limit,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: kitFieldDecoration(context,
                  label: 'Most they may owe at once',
                  prefixText: 'KES ',
                  hint: 'Empty = no limit'),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _idNumber,
              decoration: kitFieldDecoration(context,
                  label: 'ID number (optional)'),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _guarantor,
              textCapitalization: TextCapitalization.words,
              decoration: kitFieldDecoration(context,
                  label: 'Guarantor name (optional)',
                  helper: 'Someone who will vouch for this customer.'),
            ),
            const SizedBox(height: DesignSpacing.md),
            TextField(
              controller: _guarantorPhone,
              keyboardType: TextInputType.phone,
              decoration: kitFieldDecoration(context,
                  label: 'Guarantor phone (optional)'),
            ),
            const SizedBox(height: DesignSpacing.lg),
            GradientButton(
              label: 'Save',
              icon: Icons.check_rounded,
              onPressed: () {
                final t = _limit.text.trim();
                Navigator.of(context).pop({
                  'creditLimit': t.isEmpty ? null : double.tryParse(t),
                  if (_idNumber.text.trim().isNotEmpty)
                    'idNumber': _idNumber.text.trim(),
                  if (_guarantor.text.trim().isNotEmpty)
                    'guarantorName': _guarantor.text.trim(),
                  if (_guarantorPhone.text.trim().isNotEmpty)
                    'guarantorPhone': _guarantorPhone.text.trim(),
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
