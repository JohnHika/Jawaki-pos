import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../domain/mpesa_models.dart';

/// Paste the M-Pesa messages you received (or an M-Pesa statement) and tick
/// off who paid which debt. One M-Pesa code can only ever clear one payment.
class MpesaMatchScreen extends StatefulWidget {
  const MpesaMatchScreen({super.key});

  @override
  State<MpesaMatchScreen> createState() => _MpesaMatchScreenState();
}

class _MpesaMatchScreenState extends State<MpesaMatchScreen> {
  final _text = TextEditingController();
  List<MpesaPayment>? _payments;
  int _skipped = 0;
  bool _busy = false;
  String? _error;

  /// code -> who it settles. A missing key means "leave it for now".
  final Map<String, MpesaSuggestion> _chosen = {};
  final Set<String> _ignore = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.trim().isEmpty) return;
    setState(() => _text.text = data.text!);
  }

  Future<void> _read() async {
    if (_text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final json = await getIt<ApiClient>().parseMpesaMessages(_text.text);
      final list = <MpesaPayment>[
        for (final raw in (json['entries'] as List?) ?? const [])
          if (raw is Map) MpesaPayment.fromJson(raw.cast<String, dynamic>()),
      ];
      if (!mounted) return;
      setState(() {
        _payments = list;
        _skipped = asInt(json['skipped']);
        _chosen.clear();
        _ignore.clear();
        // Only pre-tick a match that is clearly right; the rest is the owner's call.
        for (final p in list) {
          if (!p.isNew || p.suggestions.isEmpty) continue;
          final best = p.suggestions.first;
          if (best.confidence == 'HIGH') _chosen[p.code] = best;
        }
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  Future<void> _apply() async {
    final payments = _payments ?? const [];
    final toApply = [
      for (final p in payments)
        if (_chosen[p.code] != null)
          {
            ...p.toItemJson(),
            if (_chosen[p.code]!.isShop)
              'debtorId': _chosen[p.code]!.id
            else
              'customerId': _chosen[p.code]!.id,
          },
    ];
    final toIgnore = [
      for (final p in payments)
        if (_ignore.contains(p.code)) p.toItemJson(),
    ];
    if (toApply.isEmpty && toIgnore.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = getIt<ApiClient>();
      var recorded = 0.0;
      var failed = 0;
      final notes = <String>[];
      if (toApply.isNotEmpty) {
        final json = await api.applyMpesaPayments(toApply);
        for (final r in (json['results'] as List?) ?? const []) {
          if (r is! Map) continue;
          if (r['ok'] == true) {
            recorded += asDouble(r['applied']);
          } else {
            failed++;
            if (r['message'] != null) notes.add('${r['code']}: ${r['message']}');
          }
        }
      }
      if (toIgnore.isNotEmpty) await api.ignoreMpesaPayments(toIgnore);
      if (!mounted) return;
      showGlassSnackBar(
        context,
        failed == 0
            ? 'Recorded ${kesWhole(recorded)}.'
            : 'Recorded ${kesWhole(recorded)}. $failed could not be recorded.',
        icon: failed == 0
            ? Icons.check_circle_outline_rounded
            : Icons.warning_amber_rounded,
        color: failed == 0 ? DesignColors.success : DesignColors.warning,
      );
      // Read again so recorded payments show as done and nothing is counted twice.
      await _read();
      if (notes.isNotEmpty && mounted) setState(() => _error = notes.join('\n'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    final selected = _chosen.length;
    final ignored = _ignore.length;
    final total = _chosen.entries.fold<double>(0, (sum, e) {
      final p = payments?.firstWhere((x) => x.code == e.key);
      return sum + (p?.amount ?? 0);
    });

    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Match M-Pesa',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      bottomNavigationBar: (selected + ignored) == 0
          ? null
          : SafeArea(
              child: PinnedActionBar(
                summary: Text(
                  [
                    if (selected > 0) '$selected to record (${kesWhole(total)})',
                    if (ignored > 0) '$ignored to hide',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                ),
                child: GradientButton(
                  label: _busy ? 'Working...' : 'Confirm',
                  icon: Icons.check_rounded,
                  onPressed: _busy ? null : _apply,
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignSpacing.lg, DesignSpacing.md,
            DesignSpacing.lg, DesignSpacing.xxxl),
        children: [
          Text(
            'Copy your M-Pesa messages (or an M-Pesa statement) and paste them here. We work out who each payment is from, and you confirm.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DesignSpacing.md),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            decoration: kitFieldDecoration(context,
                label: 'M-Pesa messages',
                hint: 'QJK1A2B3C4 Confirmed. You have received Ksh1,500.00 from JOHN KAMAU 0712...'),
          ),
          const SizedBox(height: DesignSpacing.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste'),
              ),
            ),
            const SizedBox(width: DesignSpacing.sm),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : _read,
                icon: const Icon(Icons.manage_search_rounded),
                label: Text(_busy && payments == null ? 'Reading...' : 'Read messages'),
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: DesignSpacing.md),
            Text(_error!,
                style: const TextStyle(
                    color: DesignColors.error, fontWeight: FontWeight.w600)),
          ],
          if (payments != null) ...[
            const SizedBox(height: DesignSpacing.lg),
            if (payments.isEmpty)
              const EmptyState(
                icon: Icons.sms_failed_outlined,
                title: 'No payments found',
                subtitle:
                    'Only messages saying you received money are used. Check that you pasted the whole message.',
              )
            else ...[
              Text(
                '${payments.length} payment${payments.length == 1 ? '' : 's'} found'
                '${_skipped > 0 ? ' ($_skipped skipped: sent money or repeats)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: DesignSpacing.sm),
              for (final p in payments)
                _PaymentCard(
                  payment: p,
                  chosen: _chosen[p.code],
                  ignored: _ignore.contains(p.code),
                  onChoose: (s) => setState(() {
                    _ignore.remove(p.code);
                    if (s == null) {
                      _chosen.remove(p.code);
                    } else {
                      _chosen[p.code] = s;
                    }
                  }),
                  onIgnore: (v) => setState(() {
                    _chosen.remove(p.code);
                    if (v) {
                      _ignore.add(p.code);
                    } else {
                      _ignore.remove(p.code);
                    }
                  }),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.chosen,
    required this.ignored,
    required this.onChoose,
    required this.onIgnore,
  });

  final MpesaPayment payment;
  final MpesaSuggestion? chosen;
  final bool ignored;
  final ValueChanged<MpesaSuggestion?> onChoose;
  final ValueChanged<bool> onIgnore;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final done = !payment.isNew;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: Opacity(
        opacity: done ? 0.6 : 1,
        child: GlassCard(
          padding: const EdgeInsets.all(DesignSpacing.md),
          borderRadius: DesignSpacing.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(kesWhole(payment.amount),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (done)
                  StatusBadge(
                    label: payment.state == 'RECORDED' ? 'Recorded' : 'Hidden',
                    color: DesignColors.success,
                  ),
              ]),
              Text(
                [
                  if (payment.senderName != null) payment.senderName!,
                  if (payment.senderPhone != null) payment.senderPhone!,
                ].join(' · '),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${payment.code}${payment.paidAt != null ? ' · ${timeAgo(payment.paidAt!)}' : ''}',
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              if (payment.isNew) ...[
                const SizedBox(height: DesignSpacing.sm),
                if (payment.suggestions.isEmpty)
                  Text('No customer or shop matches this payment.',
                      style: TextStyle(color: secondary, fontSize: 13))
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in payment.suggestions)
                      ChoicePill(
                        label:
                            '${s.name} · owes ${kesWhole(s.outstanding)}',
                        icon: s.confidence == 'HIGH'
                            ? Icons.verified_rounded
                            : Icons.help_outline_rounded,
                        selected: chosen?.id == s.id,
                        onTap: () => onChoose(chosen?.id == s.id ? null : s),
                      ),
                  ]),
                if (chosen != null && chosen!.reasons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(chosen!.reasons.join(' · '),
                        style: TextStyle(color: secondary, fontSize: 12)),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => onIgnore(!ignored),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero),
                    child: Text(
                        ignored ? 'Undo: not a debt payment' : 'Not a debt payment'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
