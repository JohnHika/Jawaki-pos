import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';
import 'settings_desktop_widgets.dart';

/// The rules for payments the shop records itself (M-Pesa to its own till, a
/// bank transfer), as a computer settings page: one hairline group of rows with
/// the control at the right of each, and Save in the header (Ctrl+S).
///
/// It only draws. The routed screen owns the values and the saving.
class DesktopRecordedRulesView extends StatelessWidget {
  const DesktopRecordedRulesView({
    super.key,
    required this.enabled,
    required this.requireMessage,
    required this.isOwner,
    required this.saved,
    required this.limitController,
    required this.tillController,
    required this.onEnabledChanged,
    required this.onRequireMessageChanged,
    required this.onFieldChanged,
    required this.onSave,
  });

  final bool enabled;
  final bool requireMessage;
  final bool isOwner;

  /// The values on screen are already saved.
  final bool saved;
  final TextEditingController limitController;
  final TextEditingController tillController;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onRequireMessageChanged;
  final VoidCallback onFieldChanged;
  final VoidCallback onSave;

  bool get _canSave => isOwner && !saved;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    final mute = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
    );

    return CallbackShortcuts(
      bindings: {
        if (_canSave)
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Recorded payments',
              subtitle: 'Rules for money paid to your own till or bank',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                Tooltip(
                  message: 'Save rules (Ctrl+S)',
                  child: FilledButton.icon(
                    style: desktopPrimaryButton(context),
                    onPressed: _canSave ? onSave : null,
                    icon: Icon(
                      saved ? Icons.check_rounded : Icons.save_outlined,
                      size: 17,
                    ),
                    label: Text(saved ? 'Saved' : 'Save rules'),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: SingleChildScrollView(
                child: DesktopContent(
                  maxWidth: 760,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(
                          'Money your customers send to your own till or bank '
                          'can be recorded at checkout. Counterbase cannot '
                          'check it with the bank, so these payments are '
                          'marked "recorded" and follow your rules.',
                          style: mute,
                        ),
                      ),
                      if (!isOwner)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _OwnerOnly(),
                        ),
                      DesktopSettingGroup(
                        title: 'At checkout',
                        note:
                            'A code can only be recorded once. Every recorded payment saves who recorded it, who approved it and the message that was pasted. Receipts and reports always say "recorded".',
                        children: [
                          DesktopSettingRow(
                            icon: Icons.point_of_sale_rounded,
                            title: 'Allow recorded payments',
                            helper:
                                'Shows M-Pesa to our till and bank transfer at checkout.',
                            trailing: DesktopSwitch(
                              value: enabled,
                              semanticLabel: 'Allow recorded payments',
                              onChanged: isOwner ? onEnabledChanged : null,
                            ),
                          ),
                          DesktopSettingRow(
                            icon: Icons.verified_user_outlined,
                            title: 'A manager must approve above',
                            helper:
                                'A recorded payment over this amount needs a manager or owner PIN. Enter 0 to need one every time.',
                            trailing: SizedBox(
                              width: 170,
                              child: TextField(
                                controller: limitController,
                                enabled: isOwner,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.end,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => onFieldChanged(),
                                onSubmitted: (_) {
                                  if (_canSave) onSave();
                                },
                                decoration: const InputDecoration(
                                  prefixText: 'KES ',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                          DesktopSettingRow(
                            icon: Icons.sms_outlined,
                            title: 'Require the pasted M-Pesa message',
                            helper:
                                'Lets Counterbase read the code and amount, and refuse a message that does not match the sale.',
                            trailing: DesktopSwitch(
                              value: requireMessage,
                              semanticLabel:
                                  'Require the pasted M-Pesa message',
                              onChanged:
                                  isOwner ? onRequireMessageChanged : null,
                            ),
                          ),
                          DesktopSettingRow(
                            icon: Icons.storefront_outlined,
                            title: 'Your till, paybill or phone number',
                            helper:
                                'Shown at checkout so customers pay the right place.',
                            trailing: SizedBox(
                              width: 220,
                              child: TextField(
                                controller: tillController,
                                enabled: isOwner,
                                keyboardType: TextInputType.phone,
                                onChanged: (_) => onFieldChanged(),
                                onSubmitted: (_) {
                                  if (_canSave) onSave();
                                },
                                decoration: const InputDecoration(
                                  hintText: '5 123 456',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ],
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
}

class _OwnerOnly extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.panelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: p.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only the owner can change these rules.',
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
