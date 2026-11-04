import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/design_system.dart';
import '../../auth/presentation/widgets/sign_in_kit.dart';
import '../domain/licence_codec.dart';
import '../domain/licence_standing.dart';
import '../domain/setup_pricing.dart';
import 'licence_providers.dart';

/// Where a shop sees how it stands with its payments to Arche Axon and enters
/// the licence code that unlocks the next period. It works with no internet.
class PlanLicenceScreen extends ConsumerStatefulWidget {
  const PlanLicenceScreen({super.key});

  @override
  ConsumerState<PlanLicenceScreen> createState() => _PlanLicenceScreenState();
}

class _PlanLicenceScreenState extends ConsumerState<PlanLicenceScreen> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  static final _dateFmt = DateFormat('d MMM yyyy');

  String get _shopId => licenceService().shopId ?? '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isNotEmpty) setState(() => _code.text = text.trim());
  }

  Future<void> _apply() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Paste the licence code we sent you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final check = await licenceService().redeem(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (check.problem) {
        null => null,
        LicenceProblem.malformed =>
          'That does not look like a licence code. Copy the whole code again.',
        LicenceProblem.badSignature =>
          'That code is not valid. Ask us for a new one.',
        LicenceProblem.wrongShop =>
          'That code is for a different shop. Check the shop ID below with us.',
      };
    });
    if (check.isValid) {
      _code.clear();
      ref.invalidate(licenceViewProvider);
      showGlassSnackBar(context, 'Licence applied. Thank you.',
          icon: Icons.check_circle_rounded, color: DesignColors.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final view = ref.watch(licenceViewProvider);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
        ),
        title: Text('Plan and licence',
            style: DesignType.display.copyWith(
                color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: view.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text('Could not read your plan. Close and open this screen.',
                style: TextStyle(color: palette.soft)),
          ),
          data: (data) => data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text('Plans are not switched on yet.',
                        style: TextStyle(color: palette.soft)),
                  ),
                )
              : _content(palette, data),
        ),
      ),
    );
  }

  Widget _content(SignInPalette palette, LicenceView data) {
    final standing = data.standing;
    final (label, color) = switch (standing.status) {
      LicenceStatus.trial => ('Free trial', MoneyColors.verified),
      LicenceStatus.active => ('Active', MoneyColors.cash),
      LicenceStatus.grace => ('Payment overdue', MoneyColors.recorded),
      LicenceStatus.salesPaused => ('New sales paused', DesignColors.error),
    };
    final due = standing.dueAt.toLocal();
    final detail = switch (standing.status) {
      LicenceStatus.trial =>
        'Your free trial ends on ${_dateFmt.format(due)} (${_days(standing.daysLeft)} left).',
      LicenceStatus.active =>
        'Next payment due ${_dateFmt.format(due)} (${_days(standing.daysLeft)}).',
      LicenceStatus.grace =>
        'The payment due on ${_dateFmt.format(due)} is late. Everything still works for ${_days(standing.daysLeft)}.',
      LicenceStatus.salesPaused =>
        'Pay to start selling again. Your records are safe and you can still view and export them.',
    };
    final plan = data.claims?.plan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.isDark ? const Color(0xFF211C16) : const Color(0xFF1A1610),
            borderRadius: BorderRadius.circular(DesignSpacing.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan == null ? 'YOUR PLAN' : 'YOUR PLAN · ${_title(plan).toUpperCase()}',
                style: DesignType.numeric(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB3A89A),
                    letterSpacing: 1.2),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: DesignType.display.copyWith(
                            color: const Color(0xFFF6EFE6),
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(detail,
                  style: const TextStyle(
                      color: Color(0xFFB3A89A), fontSize: 14, height: 1.45)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          palette: palette,
          title: 'How to pay and unlock',
          children: [
            _Step(palette, '1', 'Pay Arche Axon.',
                'Call 0742126582 or email support@archeaxon.com to pay by M-Pesa or card.'),
            _Step(palette, '2', 'We send you a licence code.',
                'Give us your shop ID below so the code is made for your shop.'),
            _Step(palette, '3', 'Paste it here.',
                'It works with no internet. Sales start again straight away.'),
          ],
        ),
        const SizedBox(height: 14),
        _Card(
          palette: palette,
          title: 'Licence code',
          children: [
            TextField(
              controller: _code,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              style: DesignType.numeric(fontSize: 12.5, color: palette.ink),
              decoration: InputDecoration(
                hintText: 'Paste the code that starts with CBL1.',
                errorText: _error,
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SignInButton(
              label: _busy ? 'Checking…' : 'Apply code',
              onPressed: _busy ? null : _apply,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Card(
          palette: palette,
          title: 'Your shop ID',
          children: [
            Text('Give this to us when you pay.',
                style: TextStyle(color: palette.soft, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(_shopId,
                      style: DesignType.numeric(fontSize: 12.5, color: palette.ink)),
                ),
                IconButton(
                  tooltip: 'Copy shop ID',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _shopId));
                    if (!mounted) return;
                    showGlassSnackBar(context, 'Shop ID copied',
                        icon: Icons.check_circle_rounded,
                        color: DesignColors.success);
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Card(
          palette: palette,
          title: 'If a payment is late',
          children: [
            _Bullet(palette, 'You get $kGraceDays days of grace. Everything works.'),
            _Bullet(palette, 'After that, new sales pause until you pay.'),
            _Bullet(palette,
                'You can always view and export your sales, stock and customers.'),
            _Bullet(palette, 'We never charge a late fee or interest.'),
          ],
        ),
      ],
    );
  }

  String _days(int n) => n == 1 ? '1 day' : '$n days';

  String _title(String plan) =>
      plan.isEmpty ? plan : plan[0].toUpperCase() + plan.substring(1).toLowerCase();
}

class _Card extends StatelessWidget {
  const _Card({required this.palette, required this.title, required this.children});

  final SignInPalette palette;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: DesignType.display.copyWith(
                    color: palette.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.palette, this.number, this.title, this.body);

  final SignInPalette palette;
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DesignColors.accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Text(number,
                  style: TextStyle(
                      color: palette.ink, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: palette.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.palette, this.text);

  final SignInPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 10),
              child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: DesignColors.accent,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: palette.soft, fontSize: 13.5, height: 1.4)),
            ),
          ],
        ),
      );
}
