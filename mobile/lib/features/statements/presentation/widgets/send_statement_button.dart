import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
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
    final localWorkspace = getIt<AuthService>().isLocalWorkspace;
    if (localWorkspace && customerId == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('send-statement'),
        onPressed: localWorkspace
            ? () => _shareLocalStatement(context)
            : () => showStatementSheet(
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
        label: Text(localWorkspace ? 'Share local statement' : 'Send statement',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _shareLocalStatement(BuildContext context) async {
    final id = customerId;
    if (id == null) return;
    try {
      final customer = await getIt<AppDatabase>().getCustomer(id);
      if (customer == null) {
        throw StateError('This customer is not saved on this device.');
      }
      final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
      final database = getIt<AppDatabase>();
      final installments = await database.getCustomerInstallments(id);
      final sales = await database.getRecentCustomerSales(id);
      final collections = await database.getRecentCustomerCollections(id);
      final upcoming = installments.where((item) {
        final status = item['status']?.toString().toLowerCase();
        return status == 'pending' || status == 'overdue';
      }).toList();
      final user =
          getIt<AuthService>().currentUser ?? const <String, dynamic>{};
      final tenant = user['tenant'];
      final tenantName = tenant is Map
          ? tenant['name']?.toString().trim()
          : user['companyName']?.toString().trim();
      final merchantName =
          tenantName?.isNotEmpty == true ? tenantName! : 'Your shop';
      final branchName = user['branchName']?.toString().trim();
      final message = StringBuffer()
        ..writeln(merchantName)
        ..writeln('Account statement for $name')
        ..writeln(
            'Statement date: ${_statementDate(DateTime.now().toIso8601String())}');
      if (branchName?.isNotEmpty == true) {
        message.writeln('Branch: $branchName');
      }
      message.writeln(
        'Outstanding balance: ${formatMoney(balance)}',
      );
      if (sales.isNotEmpty) {
        message
          ..writeln()
          ..writeln('Recent sales:');
        for (final sale in sales) {
          final receipt = sale['receiptNumber']?.toString().trim();
          final receiptLabel = receipt == null || receipt.isEmpty
              ? sale['id']?.toString() ?? 'Sale'
              : receipt;
          message.writeln(
            '• ${_statementDate(sale['createdAt'])} · '
            '${formatMoney((sale['total'] as num?)?.toDouble() ?? 0)} · '
            '${sale['paymentMethod']?.toString() ?? 'Sale'} · $receiptLabel',
          );
        }
      }
      if (collections.isNotEmpty) {
        message
          ..writeln()
          ..writeln('Debt payments received:');
        for (final collection in collections) {
          final reference = collection['reference']?.toString().trim();
          message.writeln(
            '• ${_statementDate(collection['collectedAt'])} · '
            '${formatMoney((collection['amount'] as num?)?.toDouble() ?? 0)} · '
            '${collection['paymentMethod']?.toString() ?? 'Payment received'}'
            '${reference == null || reference.isEmpty ? '' : ' · Ref $reference'}',
          );
        }
      }
      if (upcoming.isNotEmpty) {
        message
          ..writeln()
          ..writeln('Payment schedule:');
        for (final item in upcoming) {
          final status = item['status']?.toString().toLowerCase();
          final dueDate = DateTime.tryParse(item['dueDate']?.toString() ?? '');
          final today = DateTime.now();
          final isOverdue = status == 'overdue' ||
              (dueDate != null &&
                  dueDate
                      .isBefore(DateTime(today.year, today.month, today.day)));
          message.writeln(
            '• ${formatMoney((item['amount'] as num?)?.toDouble() ?? 0)}'
            '${isOverdue ? ' overdue' : ''}'
            '${dueDate == null ? '' : ' due ${dueDate.day}/${dueDate.month}/${dueDate.year}'}',
          );
        }
      }
      if (phone?.trim().isNotEmpty == true) {
        message.writeln('\nCustomer phone: ${phone!.trim()}');
      }
      await Share.share(message.toString(), subject: 'Account statement');
    } catch (error) {
      if (!context.mounted) return;
      showGlassSnackBar(
        context,
        error is StateError
            ? error.message.toString()
            : 'Could not prepare this statement from on-device records.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
  }
}

String _statementDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date unavailable';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
