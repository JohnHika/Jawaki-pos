import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/export_document_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/shop_name.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/coupon_models.dart';
import '../providers/coupon_provider.dart';

/// Discount codes the shop gives its customers. Each use is recorded against
/// the cashier who took it, so a code can be a reason to come back without
/// being a hole in the till.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider);
    final report = ref.watch(couponReportProvider);
    final canManage = ref.watch(permissionsProvider).has('coupons.manage');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> refresh() async {
      ref.invalidate(couponsProvider);
      ref.invalidate(couponReportProvider);
    }

    return Scaffold(
      appBar: BrandedAppBar(
        title: ref
            .watch(businessLayoutProvider)
            .actionLabel('/coupons', 'Coupons'),
        showBackButton: GoRouter.of(context).canPop(),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () async {
                await _openEditor(context);
                await refresh();
              },
              backgroundColor: DesignColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New coupon'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: coupons.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(DesignSpacing.lg),
            children: [
              InlineRetryNotice(message: apiErrorMessage(e), onRetry: refresh),
            ],
          ),
          data: (rows) => ListView(
            padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 120),
            children: [
              report.maybeWhen(
                data: (r) => _ReportCard(report: r, isDark: isDark),
                orElse: () => const SizedBox.shrink(),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.local_offer_outlined,
                    title: 'No coupons yet',
                    subtitle:
                        'Make a code like SAVE10, send it to your customers on WhatsApp, and the till takes the discount off when they use it.',
                  ),
                )
              else
                for (final c in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DesignSpacing.sm),
                    child: _CouponTile(
                      coupon: c,
                      onTap: () async {
                        await _openEditor(context, existing: c);
                        await refresh();
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {ShopCoupon? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CouponEditor(existing: existing),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.isDark});

  final CouponReport report;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final topCashier = report.byCashier.isEmpty ? null : report.byCashier.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.lg),
      child: GlassCard(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        borderRadius: DesignSpacing.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last ${report.days} days',
                style:
                    TextStyle(color: secondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              report.uses == 0
                  ? 'No coupons used yet'
                  : '${report.uses} used · ${kesWhole(report.totalGiven)} given away',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (topCashier != null && report.byCashier.length > 1) ...[
              const SizedBox(height: 6),
              Text(
                'Most by ${topCashier.label}: ${topCashier.uses} (${kesWhole(topCashier.given)})',
                style: TextStyle(color: secondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CouponTile extends StatelessWidget {
  const _CouponTile({required this.coupon, required this.onTap});

  final ShopCoupon coupon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (coupon.status) {
      'ACTIVE' => ('Active', DesignColors.success),
      'SCHEDULED' => ('Starts soon', DesignColors.info),
      'EXPIRED' => ('Expired', DesignColors.error),
      'USED_UP' => ('Used up', DesignColors.warning),
      _ => ('Off', DesignColors.warning),
    };
    final bits = <String>[
      coupon.description,
      coupon.usageLabel,
      if (coupon.expiresAt != null)
        'until ${coupon.expiresAt!.day}/${coupon.expiresAt!.month}',
    ];
    return ListCard(
      leading: Icon(Icons.local_offer_rounded, color: color),
      title: coupon.code,
      subtitle: bits.join(' · '),
      trailing: StatusBadge(label: label, color: color),
      onTap: onTap,
    );
  }
}

class _CouponEditor extends StatefulWidget {
  const _CouponEditor({this.existing});

  final ShopCoupon? existing;

  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _minSpend;
  late final TextEditingController _usageLimit;
  late final TextEditingController _perCustomer;
  late bool _percent;
  late bool _active;
  int? _validDays = 30;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _code = TextEditingController(text: c?.code ?? '');
    _value = TextEditingController(text: c == null ? '' : kitNumber(c.value));
    _minSpend = TextEditingController(
        text: c?.minSpend == null ? '' : kitNumber(c!.minSpend!));
    _usageLimit = TextEditingController(
        text: c?.usageLimit == null ? '' : '${c!.usageLimit}');
    _perCustomer = TextEditingController(
        text: c?.perCustomerLimit == null ? '' : '${c!.perCustomerLimit}');
    _percent = c?.isPercent ?? true;
    _active = c?.isActive ?? true;
    if (c != null) {
      _validDays = null; // keep the existing end date unless changed
    }
  }

  @override
  void dispose() {
    for (final c in [_code, _value, _minSpend, _usageLimit, _perCustomer]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim());
  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _save() async {
    final value = _num(_value);
    if (!_isEdit) {
      if (value == null || value <= 0) {
        setState(() => _error = 'Enter how much the coupon takes off.');
        return;
      }
      if (_percent && value > 100) {
        setState(() => _error = 'A percentage cannot be more than 100.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = getIt<ApiClient>();
    final expires = _validDays == null
        ? null
        : DateTime.now()
            .add(Duration(days: _validDays!))
            .toUtc()
            .toIso8601String();
    try {
      if (_isEdit) {
        await api.updateCoupon(widget.existing!.id, {
          'isActive': _active,
          'minSpend': _num(_minSpend),
          'usageLimit': _int(_usageLimit),
          'perCustomerLimit': _int(_perCustomer),
          // Only touched when the owner picked a new length.
          if (_validDays != null) 'expiresAt': _validDays == 0 ? null : expires,
        });
      } else {
        await api.createCoupon({
          if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
          'kind': _percent ? 'PERCENT' : 'FIXED',
          'value': value,
          if (_num(_minSpend) != null) 'minSpend': _num(_minSpend),
          if (_int(_usageLimit) != null) 'usageLimit': _int(_usageLimit),
          if (_int(_perCustomer) != null)
            'perCustomerLimit': _int(_perCustomer),
          if (_validDays != null && _validDays! > 0) 'expiresAt': expires,
        });
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await getIt<ApiClient>().deleteCoupon(widget.existing!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
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
    final c = widget.existing;
    return Padding(
      padding: EdgeInsets.fromLTRB(DesignSpacing.lg, 0, DesignSpacing.lg,
          MediaQuery.of(context).viewInsets.bottom + DesignSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? c!.code : 'New coupon',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (_isEdit) ...[
              const SizedBox(height: 2),
              Text('${c!.description} · ${c.usageLabel}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: DesignSpacing.md),
            if (!_isEdit) ...[
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: kitFieldDecoration(context,
                    label: 'Code (optional)',
                    hint: 'Leave empty to make one',
                    helper: 'Letters and numbers, 3 to 20 characters'),
              ),
              const SizedBox(height: DesignSpacing.md),
              Wrap(spacing: 8, children: [
                ChoicePill(
                    label: 'Percent off',
                    selected: _percent,
                    onTap: () => setState(() => _percent = true)),
                ChoicePill(
                    label: 'Shillings off',
                    selected: !_percent,
                    onTap: () => setState(() => _percent = false)),
              ]),
              const SizedBox(height: DesignSpacing.md),
              TextField(
                controller: _value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: kitFieldDecoration(context,
                    label: _percent ? 'Percent off' : 'Amount off',
                    suffixText: _percent ? '%' : null,
                    prefixText: _percent ? null : 'KES '),
              ),
              const SizedBox(height: DesignSpacing.md),
            ],
            TextField(
              controller: _minSpend,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: kitFieldDecoration(context,
                  label: 'Minimum spend (optional)', prefixText: 'KES '),
            ),
            const SizedBox(height: DesignSpacing.md),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _usageLimit,
                  keyboardType: TextInputType.number,
                  decoration: kitFieldDecoration(context,
                      label: 'Total uses', hint: 'No limit'),
                ),
              ),
              const SizedBox(width: DesignSpacing.md),
              Expanded(
                child: TextField(
                  controller: _perCustomer,
                  keyboardType: TextInputType.number,
                  decoration: kitFieldDecoration(context,
                      label: 'Per customer', hint: 'No limit'),
                ),
              ),
            ]),
            const SizedBox(height: DesignSpacing.md),
            const FormLabel('Valid for'),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (label, days) in const [
                ('7 days', 7),
                ('30 days', 30),
                ('90 days', 90),
                ('No end', 0),
              ])
                ChoicePill(
                    label: label,
                    selected: _validDays == days,
                    onTap: () => setState(() => _validDays = days)),
            ]),
            if (_isEdit) ...[
              const SizedBox(height: DesignSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                activeThumbColor: DesignColors.accent,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Switched on'),
                subtitle:
                    const Text('Turn it off to stop it working at the till.'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: DesignSpacing.sm),
              Text(_error!,
                  style: const TextStyle(
                      color: DesignColors.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: DesignSpacing.lg),
            GradientButton(
              label: _busy
                  ? 'Saving...'
                  : (_isEdit ? 'Save changes' : 'Create coupon'),
              icon: Icons.check_rounded,
              onPressed: _busy ? null : _save,
            ),
            if (_isEdit) ...[
              const SizedBox(height: DesignSpacing.sm),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ExportDocumentService.sharePlainText(
                        c!.shareText(currentShopName()),
                        subject: 'Coupon ${c.code}'),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share code'),
                  ),
                ),
                const SizedBox(width: DesignSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c!.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')));
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                ),
              ]),
              TextButton(
                onPressed: _busy ? null : _delete,
                child: Text(
                    c!.usedCount == 0
                        ? 'Delete coupon'
                        : 'Delete (switches off, keeps history)',
                    style: const TextStyle(color: DesignColors.error)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
