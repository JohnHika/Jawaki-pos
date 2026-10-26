import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/services/update_check_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/statement_models.dart';
import '../../domain/statement_sync_recovery.dart';

/// Opens the "send a statement" sheet for a customer or a peer shop that owes.
///
/// The customer gets a link that opens a page in their browser (no app, no
/// account) showing exactly what they owe, with a PDF to download and buttons
/// to say "I have paid" or "I will pay on". The owner sees when it was opened.
Future<void> showStatementSheet(
  BuildContext context, {
  String? customerId,
  String? debtorId,
  required String name,
  String? phone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StatementSheet(
      customerId: customerId,
      debtorId: debtorId,
      name: name,
      phone: phone,
    ),
  );
}

class _StatementSheet extends ConsumerStatefulWidget {
  const _StatementSheet({
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
  ConsumerState<_StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends ConsumerState<_StatementSheet> {
  final _note = TextEditingController();
  StatementPreview? _preview;
  List<SentStatementLink> _sent = const [];
  String? _loadError;
  String? _historyLoadError;
  bool _customerNeedsSync = false;
  bool _statementServiceNeedsUpdate = false;
  bool _checkingForAppUpdate = false;
  bool _automaticCustomerSyncAttempted = false;
  bool _loading = true;
  bool _busy = false;
  int _loadGeneration = 0;
  int _historyGeneration = 0;
  String? _message;
  String _lang = 'en';
  int _days = 14;

  // The last link made for the current note/validity, so sending the same
  // statement twice (WhatsApp, then PDF) does not make a second link.
  Map<String, dynamic>? _link;
  String? _linkKey;

  ApiClient get _api => getIt<ApiClient>();

  static const _statementServiceUpdateMessage =
      'This statement service needs an update. Your customer and debt are safe. '
      'Check for a Counterbase app update; if you are already up to date, contact support.';

  String _loadErrorMessage(
    Object error, {
    required bool customerNeedsSync,
    required bool serviceNeedsUpdate,
  }) {
    if (customerNeedsSync) {
      return 'This customer or their latest sale has not synced yet.';
    }
    if (serviceNeedsUpdate) return _statementServiceUpdateMessage;
    if (error is StateError) return error.message.toString();
    return apiErrorMessage(error);
  }

  Future<void> _checkForAppUpdate() async {
    if (_checkingForAppUpdate) return;
    setState(() => _checkingForAppUpdate = true);
    try {
      final updates = getIt<UpdateCheckService>();
      await updates.checkForUpdates(force: true);
      if (!mounted) return;
      if (updates.hasOptionalUpdateAvailable) {
        await updates.showCachedOptionalUpdateDialog(context);
      } else if (updates.errorMessage != null) {
        setState(() => _message = updates.errorMessage);
      } else if (!updates.isForceUpdateRequired &&
          !updates.isPostLoginUpdateRequired) {
        setState(() => _message =
            'Counterbase is up to date. If statement sending still fails, contact support.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not check for an update. Try again from Settings.');
      }
    } finally {
      if (mounted) setState(() => _checkingForAppUpdate = false);
    }
  }

  Widget _buildCheckForAppUpdateButton() => TextButton.icon(
        onPressed: _checkingForAppUpdate ? null : _checkForAppUpdate,
        icon: _checkingForAppUpdate
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.system_update_alt_rounded),
        label: Text(
          _checkingForAppUpdate ? 'Checking…' : 'Check for app update',
        ),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
      _statementServiceNeedsUpdate = false;
    });
    // Statement history is useful, but it must not hold the balance preview
    // or the send actions hostage when that secondary request is unavailable.
    unawaited(_loadSentLinks());
    try {
      final previewResult = await _api.previewStatement(
          customerId: widget.customerId, debtorId: widget.debtorId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _preview = StatementPreview.fromJson(previewResult);
        _loading = false;
        _customerNeedsSync = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      final customerNeedsSync =
          widget.customerId != null && statementNeedsCustomerSync(e);
      setState(() {
        _loading = false;
        _customerNeedsSync = customerNeedsSync;
        _statementServiceNeedsUpdate = statementServiceNeedsUpdate(e);
        _loadError = _loadErrorMessage(
          e,
          customerNeedsSync: customerNeedsSync,
          serviceNeedsUpdate: _statementServiceNeedsUpdate,
        );
      });
      // Only a customer-specific 404 can be repaired by flushing queued data.
      // UUID validation and missing-route errors need a server update; retrying
      // customer sync cannot make those API contracts compatible.
      if (customerNeedsSync && !_automaticCustomerSyncAttempted) {
        _automaticCustomerSyncAttempted = true;
        await _syncCustomerAndRetry();
      }
    }
  }

  Future<void> _loadSentLinks() async {
    final generation = ++_historyGeneration;
    try {
      final links = await _api.getStatementLinks(
          customerId: widget.customerId, debtorId: widget.debtorId);
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _sent = links.map(SentStatementLink.fromJson).toList();
        _historyLoadError = null;
      });
    } catch (_) {
      if (!mounted || generation != _historyGeneration) return;
      setState(() {
        _historyLoadError =
            'Statement history is unavailable. You can still send a statement.';
      });
    }
  }

  Future<void> _syncCustomerAndRetry() async {
    if (_loading || widget.customerId == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final sync = getIt<SyncService>();
      // Flush any queued customer and debt-sale events before generating the
      // statement. This prevents local credit from appearing sendable before
      // the server has the customer and receivable.
      await sync.syncPendingEvents();
      if (!mounted) return;
      final customerId = widget.customerId!;
      var customerStatus = await _api.getCustomerCredit(customerId);
      if (!mounted) return;

      if (customerStatus['known'] != true) {
        final userId = getIt<AuthService>().userId;
        final deviceId = getIt<StorageService>().getDeviceId();
        if (userId == null ||
            userId.isEmpty ||
            deviceId == null ||
            deviceId.isEmpty) {
          throw StateError('Sign in again before syncing this customer.');
        }
        await sync.queueSyncItem(
          tableName: 'customers',
          recordId: customerId,
          action: SyncAction.create,
          eventType: SyncEventType.customerCreated,
          data: {
            'id': customerId,
            'name': widget.name,
            if (widget.phone?.trim().isNotEmpty == true)
              'phone': widget.phone!.trim(),
          },
          deviceId: deviceId,
          userId: userId,
        );
        if (!mounted) return;
        // A background sync may already be in progress. Give its queued work
        // a moment to finish, then retry the customer creation if needed.
        for (var attempt = 0; attempt < 4; attempt++) {
          await sync.syncPendingEvents();
          customerStatus = await _api.getCustomerCredit(customerId);
          if (!mounted || customerStatus['known'] == true) break;
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      if (!mounted) return;
      if (customerStatus['known'] != true) {
        throw StateError(
            'The customer is still waiting to sync. Check the connection and try again.');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      final customerNeedsSync = widget.customerId != null &&
          (statementNeedsCustomerSync(e) ||
              (e is StateError &&
                  e.message.toString().contains('still waiting to sync')));
      setState(() {
        _loading = false;
        _customerNeedsSync = customerNeedsSync;
        _statementServiceNeedsUpdate = statementServiceNeedsUpdate(e);
        _loadError = customerNeedsSync
            ? 'This customer record has not reached the workspace yet. Sync the customer and try again.'
            : _loadErrorMessage(
                e,
                customerNeedsSync: false,
                serviceNeedsUpdate: _statementServiceNeedsUpdate,
              );
      });
    }
  }

  Future<Map<String, dynamic>> _ensureLink() async {
    final key = '${_note.text.trim()}|$_days';
    if (_link != null && _linkKey == key) return _link!;
    final link = await _api.createStatementLink(
      customerId: widget.customerId,
      debtorId: widget.debtorId,
      message: _note.text,
      days: _days,
    );
    _link = link;
    _linkKey = key;
    return link;
  }

  /// The address and text to send. If the server does not know its own public
  /// address the link comes back as a bare path; finish it with the address
  /// this phone uses to reach the server.
  (String url, String text) _shareParts(Map<String, dynamic> link) {
    final path = '${link['path']}';
    final url = link['url']?.toString() ?? _api.absoluteUrl(path);
    final texts = (link['shareText'] as Map?)?.cast<String, dynamic>() ?? {};
    var text = '${texts[_lang] ?? texts['en'] ?? url}';
    if (link['url'] == null) text = text.replaceAll(path, url);
    return (url, text);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      // Refresh "sent before" so the new link shows up.
      await _loadSentLinks();
    } catch (e) {
      if (mounted) {
        final serviceNeedsUpdate = statementServiceNeedsUpdate(e);
        setState(() {
          _statementServiceNeedsUpdate = serviceNeedsUpdate;
          _message = serviceNeedsUpdate
              ? _statementServiceUpdateMessage
              : apiErrorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsapp() => _run(() async {
        final link = await _ensureLink();
        final (_, text) = _shareParts(link);
        final number = whatsappNumber(widget.phone);
        if (number != null) {
          final uri = Uri.parse(
              'https://wa.me/$number?text=${Uri.encodeComponent(text)}');
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            return;
          }
        }
        // No number on file, or WhatsApp is not installed: use the share sheet.
        await Share.share(text, subject: 'Your statement');
      });

  Future<void> _sharePdf() => _run(() async {
        final link = await _ensureLink();
        final (_, text) = _shareParts(link);
        final bytes =
            await _api.downloadStatementPdf('${link['path']}', lang: _lang);
        if (bytes.isEmpty) throw StateError('empty pdf');
        final dir = await getTemporaryDirectory();
        final safe = widget.name
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        final file = File(
            '${dir.path}/statement-${safe.isEmpty ? 'customer' : safe}.pdf');
        await file.writeAsBytes(Uint8List.fromList(bytes));
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          text: text,
          subject: 'Your statement',
        );
      });

  Future<void> _copyLink() => _run(() async {
        final link = await _ensureLink();
        final (url, _) = _shareParts(link);
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) setState(() => _message = 'Link copied.');
      });

  Future<void> _revoke(SentStatementLink link) => _run(() async {
        await _api.revokeStatementLink(link.id);
        if (_link != null && '${_link!['id']}' == link.id) {
          _link = null;
          _linkKey = null;
        }
      });

  Future<void> _editPaymentDetails() async {
    final current = _preview?.payInstructions ?? '';
    final controller = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How customers pay you'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 400,
          decoration: const InputDecoration(
            hintText: 'e.g. Paybill 123456, account: your name\nOr Till 987654',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await _run(() async {
      await _api.updateStatementSettings({'payInstructions': saved});
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final canManage = ref.watch(permissionsProvider).has('statements.manage');
    final preview = _preview;

    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send statement',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: DesignSpacing.xs),
            Text(widget.name, style: TextStyle(color: secondary)),
            const SizedBox(height: DesignSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(DesignSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              _statementServiceNeedsUpdate
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(DesignSpacing.md),
                      decoration: BoxDecoration(
                        color: DesignColors.warning.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.system_update_alt_rounded,
                                  color: DesignColors.warning),
                              const SizedBox(width: DesignSpacing.sm),
                              Expanded(
                                child: Text(_loadError!,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium),
                              ),
                            ],
                          ),
                          const SizedBox(height: DesignSpacing.xs),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _buildCheckForAppUpdateButton(),
                          ),
                        ],
                      ),
                    )
                  : _customerNeedsSync
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(DesignSpacing.md),
                          decoration: BoxDecoration(
                            color: DesignColors.warning.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(DesignSpacing.radiusMd),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_loadError!,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: DesignSpacing.sm),
                              FilledButton.icon(
                                onPressed:
                                    _loading ? null : _syncCustomerAndRetry,
                                icon: const Icon(Icons.sync_rounded),
                                label: const Text('Sync and try again'),
                              ),
                            ],
                          ),
                        )
                      : InlineRetryNotice(message: _loadError!, onRetry: _load)
            else if (preview != null) ...[
              GlassCard(
                padding: const EdgeInsets.all(DesignSpacing.md),
                borderRadius: DesignSpacing.radiusLg,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Owes now', style: TextStyle(color: secondary)),
                          Text(kesWhole(preview.outstanding),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    if (preview.overdue > 0)
                      StatusBadge(
                        label:
                            '${kesWhole(preview.overdue)} overdue ${preview.oldestOverdueDays}d',
                        color: DesignColors.error,
                      ),
                  ],
                ),
              ),
              if (preview.outstanding <= 0)
                Padding(
                  padding: const EdgeInsets.only(top: DesignSpacing.md),
                  child: Text('Nothing is owed, so there is nothing to send.',
                      style: TextStyle(color: secondary)),
                )
              else ...[
                const SizedBox(height: DesignSpacing.md),
                if (preview.payInstructions == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignSpacing.md),
                    child: InkWell(
                      onTap: canManage ? _editPaymentDetails : null,
                      child: Container(
                        padding: const EdgeInsets.all(DesignSpacing.md),
                        decoration: BoxDecoration(
                          color: DesignColors.warning.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(DesignSpacing.radiusMd),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded,
                              color: DesignColors.warning, size: 20),
                          const SizedBox(width: DesignSpacing.sm),
                          Expanded(
                            child: Text(
                              canManage
                                  ? 'Add your Paybill or Till number so customers know how to pay. Tap here.'
                                  : 'Ask the owner to add the Paybill or Till number customers should pay to.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                TextField(
                  controller: _note,
                  maxLength: 280,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: kitFieldDecoration(context,
                      label: 'Personal note (optional)',
                      hint: 'e.g. Please clear the overdue part this week'),
                ),
                const FormLabel('Language'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  ChoicePill(
                      label: 'English',
                      selected: _lang == 'en',
                      onTap: () => setState(() => _lang = 'en')),
                  ChoicePill(
                      label: 'Kiswahili',
                      selected: _lang == 'sw',
                      onTap: () => setState(() => _lang = 'sw')),
                ]),
                const SizedBox(height: DesignSpacing.md),
                const FormLabel('Link works for'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  for (final d in const [7, 14, 30])
                    ChoicePill(
                        label: '$d days',
                        selected: _days == d,
                        onTap: () => setState(() => _days = d)),
                ]),
                const SizedBox(height: DesignSpacing.lg),
                GradientButton(
                  label: _busy ? 'Please wait...' : 'Send on WhatsApp',
                  icon: Icons.chat_rounded,
                  onPressed: _busy ? null : _whatsapp,
                ),
                const SizedBox(height: DesignSpacing.sm),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _sharePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Share PDF'),
                    ),
                  ),
                  const SizedBox(width: DesignSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _copyLink,
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Copy link'),
                    ),
                  ),
                ]),
                if (canManage && preview.payInstructions != null)
                  TextButton(
                      onPressed: _busy ? null : _editPaymentDetails,
                      child: const Text('Change payment details')),
              ],
            ],
            if (_message != null) ...[
              const SizedBox(height: DesignSpacing.sm),
              Text(_message!,
                  style: TextStyle(
                      color: _message == 'Link copied.'
                          ? DesignColors.success
                          : DesignColors.error,
                      fontWeight: FontWeight.w600)),
              if (_statementServiceNeedsUpdate)
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildCheckForAppUpdateButton(),
                ),
            ],
            if (_historyLoadError != null) ...[
              const SizedBox(height: DesignSpacing.md),
              InlineRetryNotice(
                message: _historyLoadError!,
                onRetry: _loadSentLinks,
              ),
            ],
            if (_sent.isNotEmpty) ...[
              const SizedBox(height: DesignSpacing.lg),
              const FormLabel('Sent before'),
              const SizedBox(height: 6),
              for (final link in _sent.take(5))
                _SentRow(link: link, onRevoke: () => _revoke(link)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SentRow extends StatelessWidget {
  const _SentRow({required this.link, required this.onRevoke});

  final SentStatementLink link;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final seen = link.viewCount == 0
        ? 'Not opened yet'
        : 'Opened ${link.viewCount} time${link.viewCount == 1 ? '' : 's'}'
            '${link.lastViewedAt != null ? ', ${timeAgo(link.lastViewedAt!)}' : ''}';
    final state = link.revoked
        ? 'Stopped'
        : link.expired
            ? 'Expired'
            : seen;
    final color = link.isLive
        ? (link.viewCount == 0 ? DesignColors.warning : DesignColors.success)
        : DesignColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.xs),
      child: Row(
        children: [
          Icon(link.viewCount > 0 ? Icons.done_all_rounded : Icons.done_rounded,
              size: 18, color: color),
          const SizedBox(width: DesignSpacing.sm),
          Expanded(
            child: Text(
              '${link.createdAt != null ? timeAgo(link.createdAt!) : ''} · $state'
              '${link.claims > 0 ? ' · ${link.claims} repl${link.claims == 1 ? 'y' : 'ies'}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (link.isLive)
            TextButton(
              onPressed: onRevoke,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: DesignColors.error),
              child: const Text('Stop'),
            ),
        ],
      ),
    );
  }
}
