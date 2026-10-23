import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'statement_share_sheet.dart';

/// "Send statement" for a customer or shop that owes. Hidden from people who
/// are not allowed to send statements.
class SendStatementButton extends ConsumerWidget {
  const SendStatementButton({
    super.key,
    this.customerId,
    this.debtorId,
    required this.name,
    this.phone,
  });

  final String? customerId;
  final String? debtorId;
  final String name;
  final String? phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(permissionsProvider).has('statements.share')) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('send-statement'),
        onPressed: () => showStatementSheet(
          context,
          customerId: customerId,
          debtorId: debtorId,
          name: name,
          phone: phone,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: DesignColors.accent,
          side: const BorderSide(color: DesignColors.accent),
          minimumSize: const Size.fromHeight(48),
        ),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Send statement',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
