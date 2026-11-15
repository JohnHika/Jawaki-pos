import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/desktop/desktop_table.dart';
import '../../../../core/desktop/desktop_widgets.dart';
import '../../../../core/theme/design_system.dart';
import '../../../catalog/presentation/desktop/desktop_button_styles.dart';

/// Where the shop's payout account stands.
enum DesktopPayoutStatus { needed, pending, verified }

/// One bank the payment partner supports.
class DesktopBank {
  const DesktopBank({required this.code, required this.name});

  final String code;
  final String name;
}

/// Customer payments setup on a computer: the payout account on the left (its
/// status and either the saved details or the form to connect one), and the
/// plain explanation of how verification and settlement work on the right.
///
/// It only draws. The routed screen owns loading, the form values and saving.
class DesktopPayoutSetupView extends StatelessWidget {
  const DesktopPayoutSetupView({
    super.key,
    required this.status,
    required this.banks,
    required this.bankCode,
    required this.accountController,
    required this.ownsAccount,
    required this.acceptedTerms,
    required this.termsLabel,
    required this.termsLink,
    required this.changing,
    required this.saving,
    required this.canSave,
    required this.onBank,
    required this.onOwnsAccount,
    required this.onAcceptedTerms,
    required this.onSave,
    required this.onRefresh,
    this.savedBankName,
    this.savedLast4 = '',
    this.savedHolder,
    this.error,
    this.accountLoadError,
    this.banksLoadError,
    this.noBanksMessage,
    this.onChange,
    this.onCancelChange,
    this.onDone,
  });

  final DesktopPayoutStatus status;
  final List<DesktopBank> banks;
  final String? bankCode;
  final TextEditingController accountController;
  final bool ownsAccount;
  final bool acceptedTerms;

  /// The "I agree to the ... terms" line with its link, and the "Read the
  /// terms" link, built by the screen so they keep the app's legal routes.
  final Widget termsLabel;
  final Widget termsLink;

  /// The shop has an account and is editing it.
  final bool changing;
  final bool saving;
  final bool canSave;
  final ValueChanged<String?> onBank;
  final ValueChanged<bool> onOwnsAccount;
  final ValueChanged<bool> onAcceptedTerms;
  final VoidCallback onSave;
  final VoidCallback onRefresh;
  final String? savedBankName;
  final String savedLast4;
  final String? savedHolder;
  final String? error;
  final String? accountLoadError;
  final String? banksLoadError;
  final String? noBanksMessage;
  final VoidCallback? onChange;
  final VoidCallback? onCancelChange;
  final VoidCallback? onDone;

  bool get _hasAccount => status != DesktopPayoutStatus.needed;
  bool get _showSaved => _hasAccount && !changing;

  @override
  Widget build(BuildContext context) {
    final p = context.desktop;
    return CallbackShortcuts(
      bindings: {
        if (!_showSaved && canSave)
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: 'Customer payments',
              subtitle: 'Where your sales money goes',
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: SingleChildScrollView(
                child: DesktopContent(
                  maxWidth: 1040,
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (accountLoadError != null)
                        _problem(
                          context,
                          'Could not refresh payout details',
                          '$accountLoadError The saved payout status could not '
                              'be confirmed, so payout changes are paused until '
                              'it loads successfully.',
                        ),
                      if (banksLoadError != null)
                        _problem(
                          context,
                          'Could not load supported banks',
                          '$banksLoadError Your saved payout status is still '
                              'shown. Refresh before changing payout details.',
                        ),
                      LayoutBuilder(builder: (context, c) {
                        final account = _accountPanel(context);
                        final notes = _notesPanel(context);
                        if (c.maxWidth < 820) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              account,
                              const SizedBox(height: 16),
                              notes,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: account),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: notes),
                          ],
                        );
                      }),
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

  Widget _problem(BuildContext context, String title, String message) {
    final p = context.desktop;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: DesignColors.warning.withValues(alpha: p.dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DesignColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.cloud_off_rounded,
                size: 17, color: DesignColors.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: GoogleFonts.plusJakartaSans(
                    color: p.textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: desktopLinkButton(context),
            onPressed: onRefresh,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  (String, Color) get _chip => switch (status) {
        DesktopPayoutStatus.verified => ('Verified', DesignColors.success),
        DesktopPayoutStatus.pending => ('Verification pending', DesignColors.warning),
        DesktopPayoutStatus.needed => ('Not connected', DesignColors.warning),
      };

  Widget _accountPanel(BuildContext context) {
    final chip = _chip;
    return DesktopPanel(
      title: _showSaved
          ? 'Payout account'
          : _hasAccount
              ? 'Change payout details'
              : 'Connect payout account',
      trailing: DesktopStatusChip(label: chip.$1, color: chip.$2),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _showSaved ? _saved(context) : _form(context),
      ),
    );
  }

  Widget _row(BuildContext context, String label, Widget value) {
    final p = context.desktop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: value),
          ),
        ],
      ),
    );
  }

  Widget _saved(BuildContext context) {
    final p = context.desktop;
    final verified = status == DesktopPayoutStatus.verified;
    final body = GoogleFonts.plusJakartaSans(
      color: p.textMuted,
      fontSize: 13,
      height: 1.45,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: p.border),
        _row(context, 'Bank',
            DesktopCellText(savedBankName ?? 'Saved bank', strong: true)),
        Divider(height: 1, color: p.border),
        _row(
          context,
          'Account number',
          DesktopCellText(
            savedLast4.isEmpty ? '—' : '•••• $savedLast4',
            numeric: true,
          ),
        ),
        if ((savedHolder ?? '').isNotEmpty) ...[
          Divider(height: 1, color: p.border),
          _row(context, 'Account holder', DesktopCellText(savedHolder!)),
        ],
        Divider(height: 1, color: p.border),
        const SizedBox(height: 14),
        Text(
          verified
              ? 'The payment partner has verified this payout account. New customer payments will use it. Payments already started keep their original payout route.'
              : 'Waiting for the Counterbase team to verify this shop subaccount. Customer M-Pesa and debt payments stay off until approval; cash sales are available now.',
          style: body,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              style: desktopSecondaryButton(context),
              onPressed: onChange,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(verified
                  ? 'Change payout details'
                  : 'Edit submitted details'),
            ),
            if (verified && onDone != null) ...[
              const SizedBox(width: 8),
              TextButton(
                style: desktopLinkButton(context),
                onPressed: onDone,
                child: const Text('Done'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final p = context.desktop;
    final known = banks.any((b) => b.code == bankCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('bank:$bankCode:${banks.length}'),
          initialValue: known ? bankCode : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Bank',
            prefixIcon: Icon(Icons.account_balance_outlined, size: 20),
          ),
          items: [
            for (final bank in banks)
              DropdownMenuItem<String>(
                value: bank.code,
                child: Text(bank.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: saving || banks.isEmpty ? null : onBank,
        ),
        if (banks.isEmpty && noBanksMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            noBanksMessage!,
            style: GoogleFonts.plusJakartaSans(
              color: p.dark ? DesignColors.warning : const Color(0xFF8A5A00),
              fontSize: 12.5,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: accountController,
          enabled: !saving,
          keyboardType: TextInputType.number,
          autofillHints: const [],
          decoration: const InputDecoration(
            labelText: 'Business bank account number',
            prefixIcon: Icon(Icons.numbers_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 10),
        _check(
          context,
          ownsAccount,
          saving ? null : onOwnsAccount,
          const Text('I confirm this account belongs to my business'),
        ),
        _check(context, acceptedTerms, saving ? null : onAcceptedTerms,
            termsLabel),
        Align(alignment: Alignment.centerLeft, child: termsLink),
        const SizedBox(height: 8),
        Text(
          'Only your bank and account number are needed. Never enter a bank password, PIN, or OTP here.',
          style: GoogleFonts.plusJakartaSans(
            color: p.textMuted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: GoogleFonts.plusJakartaSans(
              color: p.dark ? DesignColors.error : const Color(0xFFB42318),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Tooltip(
              message: 'Ctrl+S',
              child: FilledButton.icon(
                style: desktopPrimaryButton(context),
                onPressed: canSave ? onSave : null,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined, size: 17),
                label: Text(
                  saving
                      ? 'Verifying payout details…'
                      : _hasAccount
                          ? 'Update payout account'
                          : 'Connect payout account',
                ),
              ),
            ),
            if (changing && onCancelChange != null) ...[
              const SizedBox(width: 8),
              TextButton(
                style: desktopLinkButton(context),
                onPressed: saving ? null : onCancelChange,
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _check(
    BuildContext context,
    bool value,
    ValueChanged<bool>? onChanged,
    Widget label,
  ) {
    final p = context.desktop;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      hoverColor: p.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: DefaultTextStyle.merge(
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
                child: label,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notesPanel(BuildContext context) {
    final p = context.desktop;
    Widget block(String title, String text) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: p.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: GoogleFonts.plusJakartaSans(
                color: p.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        );
    return DesktopPanel(
      title: 'How it works',
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            block(
              'Where the money goes',
              'Add a business bank account for the payment partner to route customer M-Pesa and debt payments after verification. Cash sales remain available without payout setup. Your Counterbase plan is billed separately.',
            ),
            Divider(height: 28, color: p.border),
            block(
              'Verification and payout timing',
              'Customer M-Pesa and debt payments go to the verified bank account shown here, then settle on the payment partner’s schedule. This setup cannot send those sales directly to an M-Pesa wallet. The payment partner must verify new or changed bank details first.',
            ),
            Divider(height: 28, color: p.border),
            block(
              'Name on the M-Pesa prompt',
              'The prompt uses the shared business label for this integration, so it may not show each shop’s name. Counterbase receipts show the shop name.',
            ),
          ],
        ),
      ),
    );
  }
}
