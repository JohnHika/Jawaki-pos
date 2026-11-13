import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_split.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import '../../domain/coupon_models.dart';

/// The server-backed coupon list on a computer, with the selected code beside
/// its details. The route owns loading, permissions and editor actions.
class DesktopCouponsView extends StatefulWidget {
  const DesktopCouponsView({
    super.key,
    required this.title,
    required this.coupons,
    required this.report,
    required this.loading,
    required this.reportLoading,
    required this.canCreate,
    required this.onEdit,
    required this.onRefresh,
    this.errorMessage,
    this.reportErrorMessage,
    this.onCreate,
  });

  final String title;
  final List<ShopCoupon> coupons;
  final CouponReport? report;
  final bool loading;
  final bool reportLoading;
  final String? errorMessage;
  final String? reportErrorMessage;
  final bool canCreate;
  final VoidCallback? onCreate;
  final ValueChanged<ShopCoupon> onEdit;
  final VoidCallback onRefresh;

  @override
  State<DesktopCouponsView> createState() => _DesktopCouponsViewState();
}

class _DesktopCouponsViewState extends State<DesktopCouponsView> {
  String _query = '';
  String? _selectedId;

  List<ShopCoupon> get _rows {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.coupons;
    return widget.coupons
        .where((coupon) =>
            coupon.code.toLowerCase().contains(query) ||
            (coupon.name?.toLowerCase().contains(query) ?? false) ||
            coupon.description.toLowerCase().contains(query))
        .toList();
  }

  ShopCoupon? _couponById(String? id) {
    if (id == null) return null;
    for (final coupon in widget.coupons) {
      if (coupon.id == id) return coupon;
    }
    return null;
  }

  void _select(ShopCoupon? coupon) => setState(() => _selectedId = coupon?.id);

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final rows = _rows;
    final selected = _couponById(_selectedId);

    return CallbackShortcuts(
      bindings: {
        if (selected != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => _select(null),
      },
      child: Focus(
        canRequestFocus: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: widget.title,
              subtitle: 'Discount codes and their recorded use.',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                IconButton(
                  key: const ValueKey('coupons-refresh'),
                  tooltip: 'Refresh coupons',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                if (widget.canCreate && widget.onCreate != null)
                  FilledButton.icon(
                    key: const ValueKey('coupons-create'),
                    style: desktopPrimaryButton(context),
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('New coupon'),
                  ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: DesktopInspectorLayout(
                inspectorWidth: 340,
                onClose: () => _select(null),
                inspector:
                    selected == null ? null : _inspector(context, selected),
                main: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    14,
                    selected == null ? 24 : 16,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _activity(context),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _query.trim().isEmpty
                                  ? '${widget.coupons.length} ${widget.coupons.length == 1 ? 'coupon' : 'coupons'}'
                                  : '${rows.length} of ${widget.coupons.length} coupons',
                              style: GoogleFonts.plusJakartaSans(
                                color: p.textMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DesktopSearchField(
                            key: const ValueKey('coupons-search'),
                            width: 250,
                            hint: 'Search codes',
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                                _selectedId = null;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: p.dark ? p.panelAlt : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.border),
                          ),
                          child: DesktopDataTable<ShopCoupon>(
                            rows: rows,
                            rowId: (coupon) => coupon.id,
                            selectedId: _selectedId,
                            onRowSelected: _select,
                            onRowActivated: widget.onEdit,
                            loading: widget.loading,
                            minWidth: 640,
                            columns: [
                              DesktopColumn<ShopCoupon>(
                                label: 'Code',
                                flex: 2,
                                minWidth: 125,
                                sortBy: (coupon) => coupon.code.toLowerCase(),
                                cell: (_, coupon) =>
                                    DesktopCellText(coupon.code, strong: true),
                              ),
                              DesktopColumn<ShopCoupon>(
                                label: 'Discount',
                                flex: 3,
                                minWidth: 180,
                                sortBy: (coupon) =>
                                    coupon.description.toLowerCase(),
                                cell: (_, coupon) => DesktopCellText(
                                  coupon.description.isEmpty
                                      ? '—'
                                      : coupon.description,
                                ),
                              ),
                              DesktopColumn<ShopCoupon>(
                                label: 'Uses',
                                width: 132,
                                sortBy: (coupon) => coupon.usedCount,
                                cell: (_, coupon) => DesktopCellText(
                                  coupon.usageLabel,
                                  numeric: true,
                                ),
                              ),
                              DesktopColumn<ShopCoupon>(
                                label: 'Expires',
                                width: 110,
                                sortBy: (coupon) =>
                                    coupon.expiresAt?.millisecondsSinceEpoch ??
                                    0,
                                cell: (context, coupon) => DesktopCellText(
                                  coupon.expiresAt == null
                                      ? '—'
                                      : MaterialLocalizations.of(context)
                                          .formatMediumDate(
                                          coupon.expiresAt!.toLocal(),
                                        ),
                                  muted: coupon.expiresAt == null,
                                ),
                              ),
                              DesktopColumn<ShopCoupon>(
                                label: 'Status',
                                width: 96,
                                sortBy: (coupon) => coupon.status,
                                cell: (context, coupon) {
                                  final (label, color) = _status(coupon.status);
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: DesktopStatusChip(
                                      label: label,
                                      color: color,
                                    ),
                                  );
                                },
                              ),
                            ],
                            empty: _empty(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activity(BuildContext context) {
    final report = widget.report;
    if (report == null) {
      final message = widget.reportErrorMessage ??
          (widget.reportLoading ? 'Loading coupon activity…' : null);
      if (message == null) return const SizedBox.shrink();
      return SizedBox(
        height: 48,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            message,
            style: GoogleFonts.plusJakartaSans(
              color: context.desktop.textMuted,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    final topCashier =
        report.byCashier.length > 1 ? report.byCashier.first : null;
    return DesktopMetricStrip(
      metrics: [
        DesktopMetric(
          label: 'Last ${report.days} days',
          value: '${report.uses} used',
          hint: report.uses == 0 ? 'No coupons used yet' : null,
        ),
        DesktopMetric(
          label: 'Given away',
          value: kesWhole(report.totalGiven),
        ),
        if (topCashier != null)
          DesktopMetric(
            label: 'Most by ${topCashier.label}',
            value: '${topCashier.uses} (${kesWhole(topCashier.given)})',
          ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    if (widget.errorMessage != null && !widget.loading) {
      return DesktopEmptyState(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load coupons",
        message: widget.errorMessage,
        action: OutlinedButton(
          style: desktopSecondaryButton(context),
          onPressed: widget.onRefresh,
          child: const Text('Try again'),
        ),
      );
    }

    if (_query.trim().isNotEmpty) {
      return DesktopEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No coupons match "${_query.trim()}"',
        message: 'Check the code or try another search.',
      );
    }

    return DesktopEmptyState(
      icon: Icons.local_offer_outlined,
      title: 'No coupons yet',
      message:
          'Create a code to offer a discount when a customer uses it at the till.',
      action: widget.canCreate && widget.onCreate != null
          ? FilledButton.icon(
              style: desktopPrimaryButton(context),
              onPressed: widget.onCreate,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('New coupon'),
            )
          : null,
    );
  }

  Widget _inspector(BuildContext context, ShopCoupon coupon) {
    final (statusLabel, statusColor) = _status(coupon.status);
    final name = coupon.name?.trim();
    return DesktopInspector(
      title: coupon.code,
      subtitle: name == null || name.isEmpty ? null : name,
      onClose: () => _select(null),
      footer: OutlinedButton.icon(
        key: const ValueKey('coupon-edit'),
        style: desktopSecondaryButton(context),
        onPressed: () => widget.onEdit(coupon),
        icon: const Icon(Icons.edit_outlined, size: 17),
        label: const Text('Edit coupon'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CouponDetail(label: 'Discount', value: coupon.description),
          _CouponDetail(
            label: 'Offer value',
            value: coupon.isPercent
                ? '${kitNumber(coupon.value)}%'
                : formatMoney(coupon.value, decimals: true),
          ),
          _CouponDetail(
            label: 'Status',
            value: statusLabel,
            valueColor: statusColor,
          ),
          _CouponDetail(label: 'Uses', value: coupon.usageLabel),
          _CouponDetail(
            label: 'Minimum spend',
            value: coupon.minSpend == null
                ? 'No minimum'
                : formatMoney(coupon.minSpend, decimals: true),
          ),
          _CouponDetail(
            label: 'Maximum discount',
            value: coupon.maxDiscount == null
                ? 'No maximum'
                : formatMoney(coupon.maxDiscount, decimals: true),
          ),
          _CouponDetail(
            label: 'Total use limit',
            value: coupon.usageLimit?.toString() ?? 'No limit',
          ),
          _CouponDetail(
            label: 'Per-customer limit',
            value: coupon.perCustomerLimit?.toString() ?? 'No limit',
          ),
          _CouponDetail(
            label: 'Starts',
            value: _date(context, coupon.startsAt, missing: 'No start date'),
          ),
          _CouponDetail(
            label: 'Expires',
            value: _date(context, coupon.expiresAt, missing: 'No end date'),
          ),
        ],
      ),
    );
  }

  String _date(BuildContext context, DateTime? date,
          {required String missing}) =>
      date == null
          ? missing
          : MaterialLocalizations.of(context).formatMediumDate(date.toLocal());

  (String, Color) _status(String status) => switch (status) {
        'ACTIVE' => ('Active', DesignColors.success),
        'SCHEDULED' => ('Starts soon', DesignColors.info),
        'EXPIRED' => ('Expired', DesignColors.error),
        'USED_UP' => ('Used up', DesignColors.warning),
        _ => ('Off', DesignColors.warning),
      };
}

class _CouponDetail extends StatelessWidget {
  const _CouponDetail({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: p.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            style: GoogleFonts.plusJakartaSans(
              color: valueColor ?? p.text,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
