import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/manual_payment.dart';

/// Seam between the screen and the network so the workflow can be tested offline.
abstract class ManualPaymentsApi {
  Future<List<ManualPaymentRequest>> list({String? status});
  Future<void> create({
    required String paymentMethod,
    required double amount,
    required String reason,
    String? notes,
  });
  Future<void> approve(String id);
  Future<void> reject(String id, String reason);
}

class _LiveManualPaymentsApi implements ManualPaymentsApi {
  _LiveManualPaymentsApi(this._api, this._auth);

  final ApiClient _api;
  final AuthService _auth;

  @override
  Future<List<ManualPaymentRequest>> list({String? status}) =>
      _api.getManualPaymentRequests(branchId: _auth.branchId, status: status);

  @override
  Future<void> create({
    required String paymentMethod,
    required double amount,
    required String reason,
    String? notes,
  }) async {
    final branchId = _auth.branchId;
    if (branchId == null || branchId.isEmpty) {
      throw StateError('Choose a branch before requesting a payment.');
    }
    await _api.createManualPaymentRequest(
      branchId: branchId,
      paymentMethod: paymentMethod,
      amount: amount,
      reason: reason,
      notes: notes,
    );
  }

  @override
  Future<void> approve(String id) async {
    await _api.approveManualPayment(id);
  }

  @override
  Future<void> reject(String id, String reason) async {
    await _api.rejectManualPayment(id, reason);
  }
}

final manualPaymentsApiProvider = Provider<ManualPaymentsApi>(
  (ref) => _LiveManualPaymentsApi(getIt<ApiClient>(), getIt<AuthService>()),
);

/// Manual payments: cashiers request approval for money taken outside the app
/// (bank transfer, cheque); a different manager approves or rejects it.
class ManualPaymentsScreen extends ConsumerStatefulWidget {
  const ManualPaymentsScreen({super.key});

  @override
  ConsumerState<ManualPaymentsScreen> createState() =>
      _ManualPaymentsScreenState();
}

class _ManualPaymentsScreenState extends ConsumerState<ManualPaymentsScreen> {
  static final _money = NumberFormat('#,##0.##');

  List<ManualPaymentRequest> _requests = const [];
  bool _loading = true;
  String? _error;
  bool _pendingOnly = true;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(manualPaymentsApiProvider)
          .list(status: _pendingOnly ? 'PENDING' : null);
      if (!mounted) return;
      setState(() {
        _requests = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(e, 'Check your connection and try again.');
      });
    }
  }

  Future<void> _decide(
    ManualPaymentRequest request,
    Future<void> Function() action,
    String done,
  ) async {
    setState(() => _busy.add(request.id));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageFor(e, 'That didn’t go through.'))));
    } finally {
      if (mounted) setState(() => _busy.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionsProvider);
    final userId = ref.watch(currentUserProvider)?['id']?.toString();
    final canApprove = permissions.has('payments.manual_approve');
    final canRequest = permissions.canMakeSales;

    return Scaffold(
      appBar: const BrandedAppBar(title: 'Manual Payments'),
      floatingActionButton: canRequest
          ? FloatingActionButton.extended(
              key: const ValueKey('manual-new'),
              onPressed: _showRequestSheet,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Request approval'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 96),
          children: <Widget>[
            Text(
              canApprove
                  ? 'Review payments taken outside the app before they count.'
                  : 'Ask a manager to approve a payment taken outside the app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: DesignSpacing.md),
            Wrap(spacing: DesignSpacing.sm, children: <Widget>[
              ChoiceChip(
                label: const Text('Pending'),
                selected: _pendingOnly,
                onSelected: (_) {
                  if (_pendingOnly) return;
                  _pendingOnly = true;
                  _load();
                },
              ),
              ChoiceChip(
                label: const Text('All'),
                selected: !_pendingOnly,
                onSelected: (_) {
                  if (!_pendingOnly) return;
                  _pendingOnly = false;
                  _load();
                },
              ),
            ]),
            const SizedBox(height: DesignSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(DesignSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Couldn’t load manual payments',
                subtitle: _error,
                actionLabel: 'Retry',
                iconColor: DesignColors.error,
                onAction: _load,
              )
            else if (_requests.isEmpty)
              EmptyState(
                icon: Icons.fact_check_outlined,
                title: _pendingOnly
                    ? 'Nothing waiting for approval'
                    : 'No manual payments yet',
                subtitle: canRequest
                    ? 'Tap “Request approval” when a customer pays outside the app.'
                    : null,
              )
            else
              ..._requests.map((request) => _buildCard(
                    request,
                    canDecide: canApprove &&
                        request.isPending &&
                        request.requestedById != userId,
                  )),
          ],
        ),
      ),
    );
  }

  /// Same shape and height for both decisions (the theme gave the outlined
  /// button a rounded-rectangle and the filled one a pill).
  static final ButtonStyle _decisionButtonShape = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  Widget _buildCard(ManualPaymentRequest request, {required bool canDecide}) {
    final color = request.isPending
        ? DesignColors.warning
        : request.isRejected
            ? DesignColors.error
            : DesignColors.success;
    final label = request.isPending
        ? 'Pending'
        : request.isRejected
            ? 'Rejected'
            : 'Approved';
    final busy = _busy.contains(request.id);
    final when = request.createdAt == null
        ? ''
        : DateFormat('d MMM, h:mm a').format(request.createdAt!);

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: GlassCard(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text('KES ${_money.format(request.amount)}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              StatusBadge(label: label, color: color),
            ]),
            const SizedBox(height: DesignSpacing.xs),
            Text(
              '${_pretty(request.paymentMethod)} · ${request.requestNumber}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: DesignSpacing.sm),
            Text(request.reason),
            if (request.receiptNumber != null)
              Text('Sale ${request.receiptNumber}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: DesignSpacing.xs),
            Text(
              [
                if (request.requestedBy != null) 'By ${request.requestedBy}',
                if (when.isNotEmpty) when,
                if (request.approvedBy != null && !request.isPending)
                  '${request.isRejected ? 'Rejected' : 'Approved'} by ${request.approvedBy}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (request.isRejected && request.rejectionReason != null) ...<Widget>[
              const SizedBox(height: DesignSpacing.xs),
              Text('Reason: ${request.rejectionReason}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DesignColors.error)),
            ],
            if (canDecide) ...<Widget>[
              const SizedBox(height: DesignSpacing.md),
              Row(children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: ValueKey('reject-${request.id}'),
                    style: _decisionButtonShape,
                    onPressed: busy ? null : () => _showRejectSheet(request),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: ValueKey('approve-${request.id}'),
                    style: _decisionButtonShape,
                    onPressed: busy
                        ? null
                        : () => _decide(
                              request,
                              () => ref
                                  .read(manualPaymentsApiProvider)
                                  .approve(request.id),
                              'Payment approved',
                            ),
                    child: Text(busy ? 'Working…' : 'Approve'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRejectSheet(ManualPaymentRequest request) async {
    final reason = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            DesignSpacing.lg,
            0,
            DesignSpacing.lg,
            MediaQuery.of(sheetContext).viewInsets.bottom + DesignSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Reject KES ${_money.format(request.amount)}?',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                key: const ValueKey('reject-reason'),
                controller: reason,
                maxLength: 500,
                decoration: InputDecoration(
                    labelText: 'Why is it being rejected?', errorText: error),
              ),
              const SizedBox(height: DesignSpacing.md),
              SizedBox(
                width: double.infinity,
                height: DesignSpacing.huge,
                child: FilledButton(
                  key: const ValueKey('reject-confirm'),
                  style: FilledButton.styleFrom(
                      backgroundColor: DesignColors.error),
                  onPressed: () {
                    final text = reason.text.trim();
                    if (text.length < 3) {
                      setSheetState(() => error = 'Give a short reason');
                      return;
                    }
                    Navigator.pop(sheetContext);
                    _decide(
                      request,
                      () => ref
                          .read(manualPaymentsApiProvider)
                          .reject(request.id, text),
                      'Payment rejected',
                    );
                  },
                  child: const Text('Reject payment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Controllers are not disposed here: the sheet is still animating out when
    // this future completes, and disposing them early asserts in TextField.
  }

  Future<void> _showRequestSheet() async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final notes = TextEditingController();
    String method = 'bank_transfer';
    String? error;
    bool saving = false;

    final created = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            DesignSpacing.lg,
            0,
            DesignSpacing.lg,
            MediaQuery.of(sheetContext).viewInsets.bottom + DesignSpacing.lg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Request payment approval',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: DesignSpacing.md),
                Wrap(spacing: DesignSpacing.sm, children: <Widget>[
                  for (final option in const <String>[
                    'bank_transfer',
                    'cheque',
                    'other'
                  ])
                    ChoiceChip(
                      label: Text(_pretty(option)),
                      selected: method == option,
                      onSelected: (_) => setSheetState(() => method = option),
                    ),
                ]),
                const SizedBox(height: DesignSpacing.md),
                TextField(
                  key: const ValueKey('manual-amount'),
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (KES)'),
                ),
                const SizedBox(height: DesignSpacing.md),
                TextField(
                  key: const ValueKey('manual-reason'),
                  controller: reason,
                  maxLength: 500,
                  decoration: const InputDecoration(
                      labelText: 'What was paid and how?'),
                ),
                TextField(
                  controller: notes,
                  decoration:
                      const InputDecoration(labelText: 'Reference (optional)'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: DesignSpacing.sm),
                    child: Text(error!,
                        style: const TextStyle(color: DesignColors.error)),
                  ),
                const SizedBox(height: DesignSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: DesignSpacing.huge,
                  child: FilledButton(
                    key: const ValueKey('manual-submit'),
                    onPressed: saving
                        ? null
                        : () async {
                            final parsed = double.tryParse(amount.text.trim());
                            if (parsed == null || parsed <= 0) {
                              setSheetState(() =>
                                  error = 'Amount must be greater than zero');
                              return;
                            }
                            if (reason.text.trim().length < 3) {
                              setSheetState(
                                  () => error = 'Add a short description');
                              return;
                            }
                            setSheetState(() {
                              saving = true;
                              error = null;
                            });
                            try {
                              await ref.read(manualPaymentsApiProvider).create(
                                    paymentMethod: method,
                                    amount: parsed,
                                    reason: reason.text.trim(),
                                    notes: notes.text.trim().isEmpty
                                        ? null
                                        : notes.text.trim(),
                                  );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            } catch (e) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                saving = false;
                                error = _messageFor(
                                    e, 'Couldn’t send the request. Try again.');
                              });
                            }
                          },
                    child: Text(saving ? 'Sending…' : 'Send for approval'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (created == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to a manager for approval')));
      await _load();
    }
  }

  static String _pretty(String value) {
    final words = value.replaceAll('_', ' ').trim();
    if (words.isEmpty) return value;
    return words[0].toUpperCase() + words.substring(1);
  }

  static String _messageFor(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        final message = data['message'];
        return message is List ? message.join(', ') : message.toString();
      }
    }
    if (error is StateError) return error.message;
    return fallback;
  }
}
