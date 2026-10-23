import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../domain/accountability_models.dart';
import '../providers/accountability_provider.dart';

/// The owner's rules: how strict the till is about prices, discounts and
/// credit, and what is worth a phone alert.
class AccountabilityRulesScreen extends ConsumerWidget {
  const AccountabilityRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(accountabilityRulesProvider);
    return Scaffold(
      appBar: BrandedAppBar(
        title: 'Shop Rules',
        showBackButton: GoRouter.of(context).canPop(),
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(DesignSpacing.lg),
          child: InlineRetryNotice(
            message: apiErrorMessage(e),
            onRetry: () => ref.invalidate(accountabilityRulesProvider),
          ),
        ),
        data: (r) => _RulesForm(initial: r),
      ),
    );
  }
}

class _RulesForm extends ConsumerStatefulWidget {
  const _RulesForm({required this.initial});

  final AccountabilityRules initial;

  @override
  ConsumerState<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends ConsumerState<_RulesForm> {
  late String _priceMode;
  late String _creditMode;
  late bool _pushHigh;
  late bool _summaryEnabled;
  late int _summaryHour;
  bool _saving = false;

  late final TextEditingController _maxDiscount;
  late final TextEditingController _minMargin;
  late final TextEditingController _defaultLimit;
  late final TextEditingController _overdueDays;
  late final TextEditingController _voidAmount;
  late final TextEditingController _refundAmount;
  late final TextEditingController _writeOff;
  late final TextEditingController _cashShort;
  late final TextEditingController _priceChange;
  late final TextEditingController _stocktakeLoss;

  static String _n(num? v) => v == null ? '' : kitNumber(v);

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _priceMode = r.priceMode;
    _creditMode = r.creditMode;
    _pushHigh = r.pushHigh;
    _summaryEnabled = r.summaryEnabled;
    _summaryHour = r.summaryHour;
    _maxDiscount = TextEditingController(text: _n(r.maxDiscountPercent));
    _minMargin = TextEditingController(text: _n(r.minMarginPercent));
    _defaultLimit = TextEditingController(text: _n(r.defaultCreditLimit));
    _overdueDays = TextEditingController(text: _n(r.overdueDays));
    _voidAmount = TextEditingController(text: _n(r.alertThreshold('voidAlertAmount', 1000)));
    _refundAmount = TextEditingController(text: _n(r.alertThreshold('refundAlertAmount', 1000)));
    _writeOff = TextEditingController(text: _n(r.alertThreshold('stockWriteOffValue', 1000)));
    _cashShort = TextEditingController(text: _n(r.alertThreshold('cashShortAmount', 200)));
    _priceChange = TextEditingController(text: _n(r.alertThreshold('priceChangePercent', 10)));
    _stocktakeLoss = TextEditingController(text: _n(r.alertThreshold('stocktakeVarianceValue', 2000)));
  }

  @override
  void dispose() {
    for (final c in [
      _maxDiscount, _minMargin, _defaultLimit, _overdueDays, _voidAmount,
      _refundAmount, _writeOff, _cashShort, _priceChange, _stocktakeLoss,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'priceGuard': {
          'mode': _priceMode,
          'maxCashierDiscountPercent': _num(_maxDiscount) ?? 5,
          'minMarginPercent': _num(_minMargin) ?? 0,
        },
        'credit': {
          'mode': _creditMode,
          'defaultLimit': _num(_defaultLimit),
          'blockWhenOverdueDays': _num(_overdueDays)?.round(),
        },
        'alerts': {
          'pushHigh': _pushHigh,
          'voidAlertAmount': _num(_voidAmount) ?? 1000,
          'refundAlertAmount': _num(_refundAmount) ?? 1000,
          'stockWriteOffValue': _num(_writeOff) ?? 1000,
          'cashShortAmount': _num(_cashShort) ?? 200,
          'priceChangePercent': _num(_priceChange) ?? 10,
          'stocktakeVarianceValue': _num(_stocktakeLoss) ?? 2000,
        },
        'dailySummary': {'enabled': _summaryEnabled, 'hourLocal': _summaryHour},
      };
      await getIt<ApiClient>().updateAccountabilitySettings(body);
      ref.invalidate(accountabilityRulesProvider);
      if (!mounted) return;
      showGlassSnackBar(context, 'Rules saved',
          icon: Icons.check_circle_rounded, color: DesignColors.success);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, apiErrorMessage(e),
          icon: Icons.error_outline_rounded, color: DesignColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numberField(
    TextEditingController c,
    String label, {
    String? hint,
    String? prefix,
    String? suffix,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignSpacing.md),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: kitFieldDecoration(context,
            label: label,
            hint: hint,
            prefixText: prefix,
            suffixText: suffix,
            helper: helper),
      ),
    );
  }

  Widget _modePills(String value, ValueChanged<String> onChanged) {
    return Wrap(
      spacing: DesignSpacing.sm,
      runSpacing: DesignSpacing.sm,
      children: [
        ChoicePill(
            label: 'Off',
            selected: value == 'OFF',
            onTap: () => onChanged('OFF')),
        ChoicePill(
            label: 'Warn & tell me',
            selected: value == 'FLAG',
            onTap: () => onChanged('FLAG')),
        ChoicePill(
            label: 'Block',
            selected: value == 'BLOCK',
            color: DesignColors.error,
            onTap: () => onChanged('BLOCK')),
      ],
    );
  }

  String _modeHelp(String mode, String what) => switch (mode) {
        'OFF' => 'Not checked.',
        'BLOCK' =>
          'A cashier cannot complete $what. A manager with permission can.',
        _ => 'The sale goes through, the cashier is warned, and you are told.',
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final help =
        isDark ? DesignColors.darkTextTertiary : DesignColors.textTertiary;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                DesignSpacing.lg, DesignSpacing.md, DesignSpacing.lg, 32),
            children: [
              const SectionHeader(
                  title: 'Prices & discounts',
                  subtitle: 'What a cashier may sell for',
                  icon: Icons.sell_outlined),
              const SizedBox(height: DesignSpacing.sm),
              _modePills(_priceMode, (m) => setState(() => _priceMode = m)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignSpacing.sm),
                child: Text(_modeHelp(_priceMode, 'a sale below cost or minimum price'),
                    style: TextStyle(color: help, fontSize: 12)),
              ),
              _numberField(_maxDiscount, 'Biggest discount a cashier can give',
                  suffix: '%',
                  helper: 'Managers with discount permission are not limited.'),
              _numberField(_minMargin, 'Profit to keep above cost',
                  suffix: '%',
                  helper:
                      'Never sell under cost plus this much. 0 means just "not below cost".'),
              const SizedBox(height: DesignSpacing.lg),
              const SectionHeader(
                  title: 'Credit',
                  subtitle: 'Selling on debt',
                  icon: Icons.account_balance_wallet_outlined),
              const SizedBox(height: DesignSpacing.sm),
              _modePills(_creditMode, (m) => setState(() => _creditMode = m)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignSpacing.sm),
                child: Text(_modeHelp(_creditMode, 'a credit sale over the limit'),
                    style: TextStyle(color: help, fontSize: 12)),
              ),
              _numberField(_defaultLimit, 'Credit limit for customers without one',
                  prefix: 'KES ', hint: 'No limit'),
              _numberField(_overdueDays, 'Stop credit when a balance is this old',
                  suffix: 'days', hint: 'Never'),
              const SizedBox(height: DesignSpacing.lg),
              const SectionHeader(
                  title: 'When to tell me',
                  subtitle: 'Bigger than this is marked serious',
                  icon: Icons.notifications_active_outlined),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send serious alerts to my phone'),
                value: _pushHigh,
                activeThumbColor: DesignColors.accent,
                onChanged: (v) => setState(() => _pushHigh = v),
              ),
              _numberField(_voidAmount, 'A voided sale of', prefix: 'KES '),
              _numberField(_refundAmount, 'A refund of', prefix: 'KES '),
              _numberField(_writeOff, 'Stock written off worth', prefix: 'KES '),
              _numberField(_cashShort, 'A till short by', prefix: 'KES '),
              _numberField(_stocktakeLoss, 'A stock count losing', prefix: 'KES '),
              _numberField(_priceChange, 'A product price changing by', suffix: '%'),
              const SizedBox(height: DesignSpacing.lg),
              const SectionHeader(
                  title: 'Daily summary',
                  subtitle: 'How the day went, sent to your phone',
                  icon: Icons.summarize_outlined),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send me a summary each evening'),
                value: _summaryEnabled,
                activeThumbColor: DesignColors.accent,
                onChanged: (v) => setState(() => _summaryEnabled = v),
              ),
              if (_summaryEnabled) ...[
                const FormLabel('Send it at'),
                Wrap(
                  spacing: DesignSpacing.sm,
                  runSpacing: DesignSpacing.sm,
                  children: [
                    for (final h in const [17, 18, 19, 20, 21, 22])
                      ChoicePill(
                        label: '${h > 12 ? h - 12 : h} pm',
                        selected: _summaryHour == h,
                        onTap: () => setState(() => _summaryHour = h),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        PinnedActionBar(
          child: GradientButton(
            label: 'Save rules',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
