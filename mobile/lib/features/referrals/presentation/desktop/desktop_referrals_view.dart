import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_table_frame.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// One shop the person invited.
class DesktopReferral {
  const DesktopReferral({
    required this.name,
    required this.rewarded,
    required this.daysEarned,
  });

  final String name;

  /// True once the shop has activated and the days were paid out.
  final bool rewarded;
  final int daysEarned;
}

/// What pressing "Use code" gave back.
class DesktopRedeemResult {
  const DesktopRedeemResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

/// Invite Shops on a computer: the code and the invite message on the right,
/// what it has earned and the shops invited in a table on the left.
///
/// Plain data in, callbacks out. The routed screen owns the request.
class DesktopReferralsView extends StatefulWidget {
  const DesktopReferralsView({
    super.key,
    required this.title,
    required this.code,
    required this.referredDays,
    required this.referrerDays,
    required this.rewarded,
    required this.pending,
    required this.daysEarned,
    required this.referrals,
    required this.onCopyCode,
    required this.onCopyInvite,
    required this.onRedeem,
    required this.onRefresh,
  });

  final String title;
  final String code;
  final int referredDays;
  final int referrerDays;
  final int rewarded;
  final int pending;
  final int daysEarned;
  final List<DesktopReferral> referrals;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyInvite;
  final Future<DesktopRedeemResult> Function(String code) onRedeem;
  final VoidCallback onRefresh;

  @override
  State<DesktopReferralsView> createState() => _DesktopReferralsViewState();
}

class _DesktopReferralsViewState extends State<DesktopReferralsView> {
  final _code = TextEditingController();
  bool _busy = false;
  DesktopRedeemResult? _result;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final text = _code.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await widget.onRedeem(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result.ok) _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPageHeader(
          title: widget.title,
          subtitle:
              'A shop that signs up with your code gets ${widget.referredDays} '
              'extra free days. When it activates, you get '
              '${widget.referrerDays}.',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 19),
              onPressed: widget.onRefresh,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesktopTokens.gutter),
          child: DesktopMetricStrip(
            metrics: [
              DesktopMetric(label: 'Joined', value: '${widget.rewarded}'),
              DesktopMetric(label: 'Waiting', value: '${widget.pending}'),
              DesktopMetric(
                label: 'Days earned',
                value: '${widget.daysEarned}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesktopTokens.gutter,
              0,
              DesktopTokens.gutter,
              DesktopTokens.gutter,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final table = _table(p);
                final side = _side(p);
                if (constraints.maxWidth < 760) {
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        side,
                        const SizedBox(height: 14),
                        SizedBox(height: 320, child: table),
                      ],
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: table),
                    const SizedBox(width: 20),
                    SizedBox(
                      width: 340,
                      child: SingleChildScrollView(child: side),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _table(DesktopPalette p) {
    return DesktopTableFrame(
      child: DesktopDataTable<DesktopReferral>(
        key: const ValueKey('referrals-table'),
        rows: widget.referrals,
        rowId: (r) => r.name,
        minWidth: 420,
        columns: [
          DesktopColumn<DesktopReferral>(
            label: 'Shop you invited',
            flex: 3,
            minWidth: 160,
            sortBy: (r) => r.name.toLowerCase(),
            cell: (context, r) => DesktopCellText(r.name, strong: true),
          ),
          DesktopColumn<DesktopReferral>(
            label: 'Status',
            width: 150,
            sortBy: (r) => r.rewarded ? 1 : 0,
            cell: (context, r) => DesktopStatusChip(
              label: r.rewarded ? 'Joined' : 'Waiting',
              color: r.rewarded ? DesignColors.success : DesignColors.warning,
            ),
          ),
          DesktopColumn<DesktopReferral>(
            label: 'Days earned',
            width: 120,
            numeric: true,
            sortBy: (r) => r.daysEarned,
            cell: (context, r) => Text(
              r.rewarded ? '${r.daysEarned}' : '-',
              style: DesignType.numeric(fontSize: 13, color: p.text),
            ),
          ),
        ],
        empty: const DesktopEmptyState(
          icon: Icons.storefront_outlined,
          title: 'No shops invited yet',
          message: 'Share your code with another shop owner. They show up '
              'here when they sign up.',
        ),
      ),
    );
  }

  Widget _side(DesktopPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopPanel(
          title: 'Your code',
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.code,
                key: const ValueKey('referral-code'),
                style: GoogleFonts.sora(
                  color: p.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    key: const ValueKey('referral-copy-invite'),
                    style: desktopPrimaryButton(context),
                    onPressed: widget.onCopyInvite,
                    icon: const Icon(Icons.content_copy_rounded, size: 16),
                    label: const Text('Copy invite message'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const ValueKey('referral-copy-code'),
                    style: desktopSecondaryButton(context),
                    onPressed: widget.onCopyCode,
                    child: const Text('Copy code'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paste the message into WhatsApp or a text.',
                style: GoogleFonts.plusJakartaSans(
                  color: p.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DesktopPanel(
          title: 'Have a code?',
          subtitle: 'Another shop\'s code, or a promo code from Counterbase.',
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: DesktopTokens.controlHeight,
                child: TextField(
                  key: const ValueKey('referral-redeem-field'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _redeem(),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter code',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: p.textFaint,
                      fontSize: 13.5,
                    ),
                    filled: true,
                    fillColor: p.dark ? p.panel : p.panelAlt,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesktopTokens.controlRadius),
                      borderSide: BorderSide(color: p.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesktopTokens.controlRadius),
                      borderSide: BorderSide(color: p.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(DesktopTokens.controlRadius),
                      borderSide: BorderSide(color: p.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: 8),
                Text(
                  _result!.message,
                  key: const ValueKey('referral-redeem-message'),
                  style: GoogleFonts.plusJakartaSans(
                    color: _result!.ok
                        ? (p.dark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF15803D))
                        : (p.dark
                            ? const Color(0xFFF97066)
                            : const Color(0xFFB42318)),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  key: const ValueKey('referral-redeem-button'),
                  style: desktopSecondaryButton(context),
                  onPressed: _busy ? null : _redeem,
                  child: Text(_busy ? 'Checking...' : 'Use code'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
