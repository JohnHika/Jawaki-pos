import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/format.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../domain/local_statement.dart';
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
            ? () => _chooseLocalStatement(context, ref)
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
        label: Text(localWorkspace ? 'Customer statement' : 'Send statement',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  /// PDF and spreadsheet list the whole account; the message is a short
  /// summary that fits a chat.
  Future<void> _chooseLocalStatement(BuildContext context, WidgetRef ref) async {
    final palette = SignInPalette.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: palette.page,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget option(
                String value, IconData icon, String title, String detail) =>
            ListTile(
              leading: Icon(icon, color: DesignColors.accentDark),
              title: Text(title,
                  style: TextStyle(
                      color: palette.ink, fontWeight: FontWeight.w700)),
              subtitle: Text(detail, style: TextStyle(color: palette.soft)),
              onTap: () => Navigator.of(sheetContext).pop(value),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Statement for $name',
                    style: DesignType.display.copyWith(
                        color: palette.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              option('pdf', Icons.picture_as_pdf_outlined, 'PDF statement',
                  'Every purchase and payment, with totals'),
              option('csv', Icons.table_chart_outlined, 'Spreadsheet (CSV)',
                  'Opens in Excel or Google Sheets'),
              option('text', Icons.chat_outlined, 'Short message',
                  'Balance and recent activity, for WhatsApp or SMS'),
            ],
          ),
        );
      },
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'pdf':
        await _shareLocalDocument(context, ref, pdf: true);
      case 'csv':
        await _shareLocalDocument(context, ref, pdf: false);
      default:
        await _shareLocalStatement(context);
    }
  }

  Future<void> _shareLocalDocument(
    BuildContext context,
    WidgetRef ref, {
    required bool pdf,
  }) async {
    final id = customerId;
    if (id == null) return;
    try {
      final database = getIt<AppDatabase>();
      final customer = await database.getCustomer(id);
      if (customer == null) {
        throw StateError('This customer is not saved on this device.');
      }
      final statement = LocalStatement(
        customerName: name,
        customerPhone: phone,
        balance: (customer['balance'] as num?)?.toDouble() ?? 0,
        sales: await database.getRecentCustomerSales(id, limit: 5000),
        payments: await database.getRecentCustomerCollections(id, limit: 5000),
      );
      final fileName =
          'statement_${name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
      if (!pdf) {
        final rows = <List<String>>[
          for (final sale in statement.purchases)
            [
              statementDateTime(sale['createdAt']),
              'Purchase',
              (sale['receiptNumber'] ?? sale['id'] ?? '').toString(),
              statementMethodLabel(sale['paymentMethod']?.toString()),
              ((sale['total'] as num?) ?? 0).toStringAsFixed(2),
            ],
          for (final payment in statement.payments)
            [
              statementDateTime(payment['collectedAt']),
              'Payment received',
              (payment['reference'] ?? '').toString(),
              statementMethodLabel(payment['paymentMethod']?.toString()),
              ((payment['amount'] as num?) ?? 0).toStringAsFixed(2),
            ],
        ];
        await ExportDocumentService.shareCsv(
          ExportDocumentService.buildCsv(
            const [
              'Date',
              'Type',
              'Receipt or reference',
              'Paid with',
              'Amount (KES)',
            ],
            rows,
          ),
          fileName,
        );
        return;
      }
      final identity = ref.read(tenantIdentityProvider);
      final logoBytes = await ExportDocumentService.fetchLogoBytes(
        identity.logoUrl,
        allowNetwork: false,
      );
      final bytes = await ExportDocumentService.buildPdfReport(
        title: 'Account statement: $name',
        companyName: identity.companyName,
        subtitle: [
          if (phone?.trim().isNotEmpty == true) 'Phone ${phone!.trim()}',
          'Printed ${statementDateTime(DateTime.now().toIso8601String())}',
        ].join('  ·  '),
        logoBytes: logoBytes,
        sections: [
          PdfReportSection(
            heading: 'Summary',
            headers: const ['', ''],
            rows: [
              [
                'Bought (${statement.purchases.length} purchases)',
                formatMoney(statement.totalBought, decimals: true),
              ],
              [
                'Of which on credit',
                formatMoney(statement.boughtOnCredit, decimals: true),
              ],
              [
                'Paid towards the account',
                formatMoney(statement.totalPaidOnAccount, decimals: true),
              ],
              ['Owed now', formatMoney(statement.balance, decimals: true)],
            ],
          ),
          PdfReportSection(
            heading: 'Purchases',
            headers: const ['Date', 'Receipt', 'Paid with', 'Amount'],
            rows: [
              for (final sale in statement.purchases)
                [
                  statementDateTime(sale['createdAt']),
                  (sale['receiptNumber'] ?? '').toString(),
                  statementMethodLabel(sale['paymentMethod']?.toString()),
                  formatMoney((sale['total'] as num?) ?? 0, decimals: true),
                ],
            ],
          ),
          if (statement.payments.isNotEmpty)
            PdfReportSection(
              heading: 'Payments received',
              headers: const ['Date', 'Paid with', 'Reference', 'Amount'],
              rows: [
                for (final payment in statement.payments)
                  [
                    statementDateTime(payment['collectedAt']),
                    statementMethodLabel(payment['paymentMethod']?.toString()),
                    (payment['reference'] ?? '').toString(),
                    formatMoney((payment['amount'] as num?) ?? 0,
                        decimals: true),
                  ],
              ],
            ),
        ],
      );
      await ExportDocumentService.sharePdf(bytes, fileName);
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
