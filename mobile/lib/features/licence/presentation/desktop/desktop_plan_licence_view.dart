import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';

/// The Plan and licence page on a computer: where the shop stands, the
/// licence code box beside the steps to get one, and the shop ID to quote
/// when paying. Takes plain data so a test can feed it sample values.
class DesktopPlanLicenceView extends StatelessWidget {
  const DesktopPlanLicenceView({
    super.key,
    required this.statusLabel,
    required this.statusColor,
    required this.sellingOn,
    required this.detail,
    required this.planLabel,
    required this.dueCaption,
    required this.dueLabel,
    required this.timeLeft,
    required this.shopId,
    required this.codeController,
    required this.graceDays,
    required this.onPaste,
    required this.onApply,
    required this.onCopyShopId,
    this.error,
    this.busy = false,
  });

  final String statusLabel;
  final Color statusColor;

  /// False once new sales are paused.
  final bool sellingOn;

  /// One sentence about the standing, shown under the title.
  final String detail;
  final String planLabel;

  /// "Next payment due" or "Free trial ends".
  final String dueCaption;
  final String dueLabel;
  final String timeLeft;
  final String shopId;
  final TextEditingController codeController;
  final int graceDays;
  final String? error;
  final bool busy;
  final VoidCallback onPaste;
  final VoidCallback onApply;
  final VoidCallback onCopyShopId;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return LayoutBuilder(builder: (context, outer) {
      final short = outer.maxHeight < 620;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopContent(
            maxWidth: 1100,
            child: DesktopPageHeader(
              title: 'Plan and licence',
              subtitle: short ? null : detail,
              padding: const EdgeInsets.only(top: 16),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, short ? 10 : 14, 0, 24),
              child: DesktopContent(
                maxWidth: 1100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (short)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          detail,
                          style: GoogleFonts.plusJakartaSans(
                            color: p.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    DesktopMetricStrip(metrics: [
                      DesktopMetric(
                        label: 'Standing',
                        value: statusLabel,
                        hint: sellingOn ? 'Selling is on' : 'Selling is paused',
                        hintColor: context.readable(statusColor),
                      ),
                      DesktopMetric(label: 'Plan', value: planLabel),
                      DesktopMetric(label: dueCaption, value: dueLabel),
                      DesktopMetric(label: 'Time left', value: timeLeft),
                    ]),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (context, c) {
                      final stacked = c.maxWidth < 820;
                      final left = _codePanel(context);
                      final right = _sidePanels(context);
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [left, const SizedBox(height: 16), right],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: left),
                          const SizedBox(width: 16),
                          Expanded(flex: 2, child: right),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _codePanel(BuildContext context) {
    final p = context.desktop;
    return DesktopPanel(
      title: 'Licence code',
      subtitle: 'Paste the code we sent you. It works with no internet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  () {
                if (!busy) onApply();
              },
            },
            child: TextField(
              controller: codeController,
              minLines: 4,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              style: DesignType.numeric(fontSize: 12.5, color: p.text),
              decoration: InputDecoration(
                hintText: 'Paste the code that starts with CBL1.',
                errorText: error,
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onPaste,
                icon: const Icon(Icons.content_paste_rounded, size: 17),
                label: const Text('Paste from clipboard'),
              ),
              const Spacer(),
              Text(
                'Ctrl+Enter',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textFaint,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: busy ? null : onApply,
                style: FilledButton.styleFrom(
                  backgroundColor: DesignColors.accent,
                  foregroundColor: const Color(0xFF1A1610),
                ),
                child: Text(busy ? 'Checking…' : 'Apply code'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 16),
          Text(
            'How to pay and unlock',
            style: GoogleFonts.sora(
              color: p.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const _Step('1', 'Pay Arche Axon.',
              'Call 0742126582 or email support@archeaxon.com to pay by M-Pesa or card.'),
          const _Step('2', 'We send you a licence code.',
              'Give us your shop ID so the code is made for your shop.'),
          const _Step('3', 'Paste it here.',
              'It works with no internet. Sales start again straight away.'),
        ],
      ),
    );
  }

  Widget _sidePanels(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPanel(
          title: 'Your shop ID',
          subtitle: 'Give this to us when you pay.',
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  shopId,
                  style: DesignType.numeric(fontSize: 12.5, color: p.text),
                ),
              ),
              IconButton(
                tooltip: 'Copy shop ID',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: onCopyShopId,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DesktopPanel(
          title: 'If a payment is late',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bullet('You get $graceDays days of grace. Everything works.'),
              const _Bullet('After that, new sales pause until you pay.'),
              const _Bullet(
                  'You can always view and export your sales, stock and customers.'),
              const _Bullet('We never charge a late fee or interest.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.body);

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.selected,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: p.textFaint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
