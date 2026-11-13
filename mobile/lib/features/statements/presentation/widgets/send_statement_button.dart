import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/desktop/adaptive_overlays.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/providers/tenant_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/services/httpsms_service.dart';
import '../../../../core/services/storage_service.dart';
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

  bool _canShareWithCurrentPermissions(WidgetRef ref) {
    final permissions = ref.read(permissionsProvider);
    return permissions.has('statements.share') &&
        (customerId == null || permissions.canSeeCustomers);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionsProvider);
    if (!permissions.has('statements.share') ||
        (customerId != null && !permissions.canSeeCustomers)) {
      return const SizedBox.shrink();
    }
    final localWorkspace = getIt<AuthService>().isLocalWorkspace;
    if (localWorkspace && customerId == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const ValueKey('send-statement'),
        onPressed: () {
          if (!_canShareWithCurrentPermissions(ref)) return;
          if (localWorkspace) {
            _chooseLocalStatement(context, ref);
          } else {
            showStatementSheet(
              context,
              customerId: customerId,
              debtorId: debtorId,
              name: name,
              phone: phone,
            );
          }
        },
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
  Future<void> _chooseLocalStatement(
      BuildContext context, WidgetRef ref) async {
    final desktop = context.inDesktopShell;
    final palette = desktop ? null : SignInPalette.of(context);

    Widget option(
      BuildContext sheetContext,
      String value,
      IconData icon,
      String title,
      String detail,
    ) {
      return ListTile(
        leading: Icon(
          icon,
          color: desktop ? context.desktop.accent : DesignColors.accentDark,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: desktop ? context.desktop.text : palette!.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          detail,
          style: TextStyle(
            color: desktop ? context.desktop.textMuted : palette!.soft,
          ),
        ),
        onTap: () => Navigator.of(sheetContext, rootNavigator: true).pop(value),
      );
    }

    Widget choices(BuildContext sheetContext) {
      final list = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!desktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Choose statement format',
                style: DesignType.display.copyWith(
                  color: palette!.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          option(
            sheetContext,
            'pdf',
            Icons.picture_as_pdf_outlined,
            'PDF statement',
            'Every purchase and payment, with totals',
          ),
          option(
            sheetContext,
            'csv',
            Icons.table_chart_outlined,
            'Spreadsheet (CSV)',
            'Opens in Excel or Google Sheets',
          ),
          option(
            sheetContext,
            'text',
            Icons.chat_outlined,
            'Short message',
            'Balance and recent activity, for WhatsApp or SMS',
          ),
          option(
            sheetContext,
            'httpsms',
            Icons.sms_outlined,
            'Send by SMS via HTTPSMS',
            'Queue the statement through your paired HTTPSMS phone',
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(8, desktop ? 4 : 16, 8, 16),
        child: desktop ? list : SingleChildScrollView(child: list),
      );
    }

    final choice = desktop
        ? await showAdaptiveSheetUntilClosed<String>(
            context: context,
            desktopStyle: DesktopSheetStyle.sidePanel,
            desktopWidth: 520,
            builder: (sheetContext) => DesktopScope(
              sidebarCollapsed:
                  DesktopScope.maybeOf(context)?.sidebarCollapsed ?? false,
              child: DesktopSheetFrame(
                title: 'Choose statement format',
                child: choices(sheetContext),
              ),
            ),
          )
        : await showModalBottomSheet<String>(
            context: context,
            useRootNavigator: true,
            useSafeArea: true,
            backgroundColor: palette!.page,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: choices,
          );
    if (choice == null ||
        !context.mounted ||
        !_canShareWithCurrentPermissions(ref)) {
      return;
    }
    switch (choice) {
      case 'pdf':
        await _shareLocalDocument(context, ref, pdf: true);
      case 'csv':
        await _shareLocalDocument(context, ref, pdf: false);
      case 'httpsms':
        await _sendLocalStatementSms(context, ref);
      default:
        await _shareLocalStatement(context, ref);
    }
  }

  Future<void> _shareLocalDocument(
    BuildContext context,
    WidgetRef ref, {
    required bool pdf,
  }) async {
    if (!_canShareWithCurrentPermissions(ref)) return;
    final id = customerId;
    if (id == null) return;
    try {
      final database = getIt<AppDatabase>();
      if (!_canShareWithCurrentPermissions(ref)) return;
      final customer = await database.getCustomer(id);
      if (!_canShareWithCurrentPermissions(ref)) return;
      if (customer == null) {
        throw StateError('This customer is not saved on this device.');
      }
      if (!_canShareWithCurrentPermissions(ref)) return;
      final sales = await database.getRecentCustomerSales(id, limit: 5000);
      if (!_canShareWithCurrentPermissions(ref)) return;
      final payments =
          await database.getRecentCustomerCollections(id, limit: 5000);
      if (!_canShareWithCurrentPermissions(ref)) return;
      final statement = LocalStatement(
        customerName: name,
        customerPhone: phone,
        balance: (customer['balance'] as num?)?.toDouble() ?? 0,
        sales: sales,
        payments: payments,
      );
      final fileName =
          'statement_${name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
      if (!pdf) {
        if (!_canShareWithCurrentPermissions(ref)) return;
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
        if (!_canShareWithCurrentPermissions(ref)) return;
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
      if (!_canShareWithCurrentPermissions(ref)) return;
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
                'Bought (${statement.purchases.length} ${statement.purchases.length == 1 ? 'purchase' : 'purchases'})',
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
      if (!_canShareWithCurrentPermissions(ref)) return;
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

  Future<void> _sendLocalStatementSms(
      BuildContext context, WidgetRef ref) async {
    if (!_canShareWithCurrentPermissions(ref)) return;
    final rawPhone = phone?.trim() ?? '';
    if (rawPhone.isEmpty) {
      showGlassSnackBar(
        context,
        'Add a phone number to this customer before sending an SMS.',
        icon: Icons.phone_outlined,
        color: DesignColors.warning,
      );
      return;
    }

    late final String recipient;
    try {
      recipient = HttpsmsService.normalizePhoneNumber(rawPhone);
    } on HttpsmsException catch (error) {
      showGlassSnackBar(
        context,
        error.message,
        icon: Icons.phone_outlined,
        color: DesignColors.error,
      );
      return;
    }

    try {
      final storage = getIt<StorageService>();
      final apiKey = await storage.getHttpsmsApiKey();
      final sender = await storage.getHttpsmsSenderNumber();
      if (!context.mounted || !_canShareWithCurrentPermissions(ref)) return;
      if (apiKey == null || sender == null) {
        final auth = getIt<AuthService>();
        if (auth.isLocalWorkspaceOwner) {
          showGlassSnackBar(
            context,
            'Set up HTTPSMS before sending a customer statement.',
            icon: Icons.settings_outlined,
            color: DesignColors.warning,
          );
          if (context.mounted) await context.push('/settings/httpsms');
        } else {
          showGlassSnackBar(
            context,
            'Ask the workspace owner to set up HTTPSMS in Settings.',
            icon: Icons.settings_outlined,
            color: DesignColors.warning,
          );
        }
        return;
      }

      final content = await _buildLocalStatementMessage(
        ref,
        includeCustomerPhone: false,
      );
      if (!context.mounted || !_canShareWithCurrentPermissions(ref)) return;
      await _reviewAndSendSms(
        context,
        ref: ref,
        apiKey: apiKey,
        sender: sender,
        recipient: recipient,
        content: content,
      );
    } catch (error) {
      if (!context.mounted) return;
      _showStatementError(context, error);
    }
  }

  Future<void> _reviewAndSendSms(
    BuildContext context, {
    required WidgetRef ref,
    required String apiKey,
    required String sender,
    required String recipient,
    required String content,
  }) async {
    final desktop = context.inDesktopShell;
    var consentConfirmed = false;
    var sending = false;
    var outcomeUnknown = false;
    String? sendError;

    final queued = await showAdaptiveSheetUntilClosed<bool>(
      context: context,
      desktopStyle: DesktopSheetStyle.dialog,
      desktopWidth: 620,
      builder: (overlayContext) {
        Widget review(StateSetter setState) {
          Future<void> send() async {
            if (!_canShareWithCurrentPermissions(ref)) {
              if (overlayContext.mounted) {
                Navigator.of(overlayContext, rootNavigator: true).pop(false);
              }
              return;
            }
            setState(() {
              sending = true;
              outcomeUnknown = false;
              sendError = null;
            });
            try {
              await getIt<HttpsmsService>().send(
                apiKey: apiKey,
                from: sender,
                to: recipient,
                content: content,
              );
              if (overlayContext.mounted) {
                Navigator.of(overlayContext, rootNavigator: true).pop(true);
              }
            } on HttpsmsException catch (error) {
              if (overlayContext.mounted) {
                setState(() {
                  sending = false;
                  outcomeUnknown = error.outcomeUnknown;
                  sendError = error.message;
                });
              }
            } catch (_) {
              if (overlayContext.mounted) {
                setState(() {
                  sending = false;
                  outcomeUnknown = true;
                  sendError =
                      'Could not confirm whether HTTPSMS queued the SMS. Check the HTTPSMS queue before trying again.';
                });
              }
            }
          }

          final preview = Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  Theme.of(overlayContext).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              child: SelectableText(content),
            ),
          );
          final consent = CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: consentConfirmed,
            onChanged: sending
                ? null
                : (value) => setState(() => consentConfirmed = value ?? false),
            title: const Text(
              'I confirm the customer expects this statement by SMS and has not opted out.',
            ),
          );
          const disclosure = Text(
            'The number and statement text go to HTTPSMS and your paired phone’s carrier. HTTPSMS end-to-end encryption is off for this send. Carrier rates vary; long messages may use multiple billable segments. Queueing does not confirm delivery.',
          );
          final error = sendError == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    sendError!,
                    style: const TextStyle(color: DesignColors.error),
                  ),
                );

          final cancelButton = TextButton(
            onPressed: sending
                ? null
                : () => Navigator.of(overlayContext, rootNavigator: true)
                    .pop(false),
            child: Text(
              sendError == null
                  ? 'Cancel'
                  : outcomeUnknown
                      ? 'Close and check queue'
                      : 'Close',
            ),
          );
          final sendButton = FilledButton.icon(
            onPressed:
                !consentConfirmed || sending || sendError != null ? null : send,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sms_outlined, size: 17),
            label: Text(sending ? 'Queueing…' : 'Queue SMS'),
          );
          final actions =
              sendError == null ? [cancelButton, sendButton] : [cancelButton];

          final body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('To $recipient',
                  style: Theme.of(overlayContext).textTheme.titleSmall),
              const SizedBox(height: 8),
              disclosure,
              const SizedBox(height: 12),
              preview,
              const SizedBox(height: 8),
              consent,
              error,
            ],
          );

          if (desktop) {
            return DesktopScope(
              sidebarCollapsed:
                  DesktopScope.maybeOf(context)?.sidebarCollapsed ?? false,
              child: DesktopSheetFrame(
                title: 'Review statement SMS',
                subtitle: 'Check the recipient and complete the confirmation',
                actions: actions,
                child: body,
              ),
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Review statement SMS',
                      style: Theme.of(overlayContext).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(child: body),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: sendError == null
                        ? [cancelButton, const SizedBox(width: 8), sendButton]
                        : [cancelButton],
                  ),
                ],
              ),
            ),
          );
        }

        return Consumer(
          builder: (_, modalRef, __) {
            if (!_canShareWithCurrentPermissions(modalRef)) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Statement access was revoked. Close this review.'),
              );
            }
            return StatefulBuilder(
              builder: (_, setState) => review(setState),
            );
          },
        );
      },
    );

    if (queued == true && context.mounted) {
      showGlassSnackBar(
        context,
        'Queued in HTTPSMS. Check its queue for delivery status.',
        icon: Icons.mark_chat_read_outlined,
        color: DesignColors.success,
      );
    }
  }

  Future<void> _shareLocalStatement(BuildContext context, WidgetRef ref) async {
    if (!_canShareWithCurrentPermissions(ref)) return;
    try {
      final message = await _buildLocalStatementMessage(ref);
      if (!context.mounted || !_canShareWithCurrentPermissions(ref)) return;
      await Share.share(message, subject: 'Account statement');
    } catch (error) {
      if (!context.mounted) return;
      _showStatementError(context, error);
    }
  }

  Future<String> _buildLocalStatementMessage(
    WidgetRef ref, {
    bool includeCustomerPhone = true,
  }) async {
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final id = customerId;
    if (id == null) {
      throw StateError('This customer is not saved on this device.');
    }
    final database = getIt<AppDatabase>();
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final customer = await database.getCustomer(id);
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    if (customer == null) {
      throw StateError('This customer is not saved on this device.');
    }
    final balance = (customer['balance'] as num?)?.toDouble() ?? 0;
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final installments = await database.getCustomerInstallments(id);
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final sales = await database.getRecentCustomerSales(id);
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final collections = await database.getRecentCustomerCollections(id);
    if (!_canShareWithCurrentPermissions(ref)) {
      throw StateError('Statement access was revoked.');
    }
    final upcoming = installments.where((item) {
      final status = item['status']?.toString().toLowerCase();
      return status == 'pending' || status == 'overdue';
    }).toList();
    final user = getIt<AuthService>().currentUser ?? const <String, dynamic>{};
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
    message.writeln('Outstanding balance: ${formatMoney(balance)}');
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
                dueDate.isBefore(DateTime(today.year, today.month, today.day)));
        message.writeln(
          '• ${formatMoney((item['amount'] as num?)?.toDouble() ?? 0)}'
          '${isOverdue ? ' overdue' : ''}'
          '${dueDate == null ? '' : ' due ${dueDate.day}/${dueDate.month}/${dueDate.year}'}',
        );
      }
    }
    if (includeCustomerPhone && phone?.trim().isNotEmpty == true) {
      message.writeln('\nCustomer phone: ${phone!.trim()}');
    }
    return message.toString();
  }

  void _showStatementError(BuildContext context, Object error) {
    if (!context.mounted) return;
    final message = switch (error) {
      HttpsmsException(:final message) => message,
      StateError() => error.message.toString(),
      _ => 'Could not prepare this statement from on-device records.',
    };
    showGlassSnackBar(
      context,
      message,
      icon: Icons.error_outline_rounded,
      color: DesignColors.error,
    );
  }
}

String _statementDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date unavailable';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
