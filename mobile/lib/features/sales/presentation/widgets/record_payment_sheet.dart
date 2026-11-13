import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:axon_pos/core/desktop/adaptive_overlays.dart';
import 'package:axon_pos/core/desktop/desktop_layout.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/subscription/domain/subscription_plans.dart'
    show formatKes;
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/sales/domain/recorded_payment.dart';

/// Records a payment the shop received itself, such as an M-Pesa payment to the
/// shop's own till or a bank transfer. Returns the details to save with the
/// sale, or null if the cashier cancels.
///
/// The payment is recorded, not verified. The sheet therefore reads the code
/// and amount from the pasted message, refuses a mismatch, warns that messages
/// can be forged, asks the cashier to confirm they saw the money in their own
/// M-Pesa or bank, and asks for a manager PIN above the shop's limit.
/// Checks a PIN and returns the approver, or null if it does not belong to a
/// manager or the owner. May throw a [StateError] with a message to show.
typedef ApproverCheck = Future<({String id, String name, bool isOwner})?>
    Function(String pin);

Future<RecordedPaymentDetails?> showRecordPaymentSheet(
  BuildContext context, {
  required String method,
  required double total,
  required RecordedPaymentRules rules,
  required String recorderId,
  required String recorderName,
  required ApproverCheck approverForPin,
}) {
  // On a computer the form opens as a dialog over the till, not a bottom sheet.
  if (DesktopLayout.wantsShell(context)) {
    return showAdaptiveSheet<RecordedPaymentDetails>(
      context: context,
      desktopWidth: 520,
      builder: (_) => _RecordPaymentSheet(
        method: method,
        total: total,
        rules: rules,
        recorderId: recorderId,
        recorderName: recorderName,
        approverForPin: approverForPin,
      ),
    );
  }
  return showModalBottomSheet<RecordedPaymentDetails>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: SignInPalette.of(context).page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _RecordPaymentSheet(
      method: method,
      total: total,
      rules: rules,
      recorderId: recorderId,
      recorderName: recorderName,
      approverForPin: approverForPin,
    ),
  );
}

class _RecordPaymentSheet extends StatefulWidget {
  const _RecordPaymentSheet({
    required this.method,
    required this.total,
    required this.rules,
    required this.recorderId,
    required this.recorderName,
    required this.approverForPin,
  });

  final String method;
  final double total;
  final RecordedPaymentRules rules;
  final String recorderId;
  final String recorderName;
  final ApproverCheck approverForPin;

  @override
  State<_RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<_RecordPaymentSheet> {
  final _messageController = TextEditingController();
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _seenInAccount = false;
  bool _busy = false;
  String? _error;
  ParsedMpesaMessage _parsed = const ParsedMpesaMessage();

  bool get _isMpesa => widget.method == RecordedPaymentMethod.mpesa;
  bool get _needsApproval => widget.rules.needsApproval(widget.total);

  @override
  void dispose() {
    _messageController.dispose();
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onMessageChanged(String text) {
    final parsed = parseMpesaMessage(text);
    setState(() {
      _parsed = parsed;
      _error = null;
      // Fill the code from the message so staff do not retype it, but never
      // overwrite something they typed by hand.
      if (parsed.code != null && _codeController.text.trim().isEmpty) {
        _codeController.text = parsed.code!;
      }
    });
  }

  bool _amountMatches(double? amount) =>
      amount != null && (amount * 100).round() == (widget.total * 100).round();

  String? _problem() {
    final code = _codeController.text.trim().toUpperCase();
    if (_isMpesa) {
      if (widget.rules.requireMessage && _messageController.text.trim().isEmpty) {
        return 'Paste the M-Pesa message so the code and amount can be checked.';
      }
      if (!looksLikeMpesaCode(code)) {
        return 'An M-Pesa code is 10 letters and numbers, like SKL4X9Q2TB.';
      }
      if (_parsed.code != null && _parsed.code != code) {
        return 'The code you typed is different from the one in the message.';
      }
      if (_parsed.amount != null && !_amountMatches(_parsed.amount)) {
        return 'The message says ${formatKes(_parsed.amount!)} but this sale is ${formatKes(widget.total)}.';
      }
      if (widget.rules.requireMessage && _parsed.amount == null) {
        return 'The amount could not be read from the message. Paste the full message.';
      }
    } else if (!looksLikeBankReference(code)) {
      return 'Enter the bank reference, 6 to 30 letters and numbers.';
    }
    if (!_seenInAccount) {
      return _isMpesa
          ? 'Tick the box to confirm you saw this payment in your own M-Pesa.'
          : 'Tick the box to confirm you saw this payment in your bank account.';
    }
    if (_needsApproval && _pinController.text.trim().length < 4) {
      return 'Enter a manager or owner PIN to approve this payment.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _problem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final recorderId = widget.recorderId;
    final recorderName = widget.recorderName;

    String? approverId;
    String? approverName;
    if (_needsApproval) {
      try {
        final approver =
            await widget.approverForPin(_pinController.text.trim());
        if (!mounted) return;
        if (approver == null) {
          setState(() {
            _busy = false;
            _error = 'That PIN does not belong to a manager or the owner.';
          });
          return;
        }
        // A second person must stand behind the payment, unless the owner is
        // the one recording it.
        if (approver.id == recorderId && !approver.isOwner) {
          setState(() {
            _busy = false;
            _error = 'Another manager or the owner must approve this payment.';
          });
          return;
        }
        approverId = approver.id;
        approverName = approver.name;
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : 'Could not check the PIN.';
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      RecordedPaymentDetails(
        method: widget.method,
        code: _codeController.text.trim().toUpperCase(),
        amount: widget.total,
        recordedById: recorderId,
        recordedByName: recorderName,
        approvedById: approverId,
        approvedByName: approverName,
        message:
            _messageController.text.trim().isEmpty ? null : _messageController.text,
        recordedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final code = _codeController.text.trim().toUpperCase();
    final recorderName = widget.recorderName;
    final received = _parsed.receivedAt;
    final stale = received != null &&
        DateTime.now().difference(received) > kRecordedPaymentFreshness;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isMpesa ? 'Record M-Pesa payment' : 'Record bank transfer',
                    style: DesignType.display.copyWith(
                      color: palette.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: palette.soft),
                ),
              ],
            ),
            Text(
              'Amount due ${formatKes(widget.total)}',
              style: DesignType.numeric(fontSize: 15, color: palette.soft),
            ),
            const SizedBox(height: 16),
            if (_isMpesa) ...[
              Text('Paste the M-Pesa message',
                  style: TextStyle(
                      color: palette.soft,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _messageController,
                onChanged: _onMessageChanged,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  hintText:
                      'SKL4X9Q2TB Confirmed. Ksh4,200.00 received from …',
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(_isMpesa ? 'M-Pesa code' : 'Bank reference',
                style: TextStyle(
                    color: palette.soft,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _codeController,
              onChanged: (_) => setState(() => _error = null),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/]')),
                LengthLimitingTextInputFormatter(_isMpesa ? 10 : 30),
              ],
              style: DesignType.numeric(fontSize: 16, color: palette.ink),
              decoration: InputDecoration(
                hintText: _isMpesa ? 'SKL4X9Q2TB' : 'Reference from the bank',
              ),
            ),
            if (_isMpesa && _parsed.amount != null) ...[
              const SizedBox(height: 12),
              _CheckRow(
                ok: _amountMatches(_parsed.amount),
                title: _amountMatches(_parsed.amount)
                    ? 'Amount matches: ${formatKes(_parsed.amount!)}'
                    : 'Amount differs: ${formatKes(_parsed.amount!)}',
                detail: _amountMatches(_parsed.amount)
                    ? 'It equals the amount due.'
                    : 'It must equal ${formatKes(widget.total)}.',
              ),
            ],
            if (_isMpesa && stale) ...[
              const SizedBox(height: 8),
              const _CheckRow(
                ok: false,
                warn: true,
                title: 'This message is old',
                detail: 'It was received more than 6 hours ago. Check it is for this sale.',
              ),
            ],
            if (code.isNotEmpty) ...[
              const SizedBox(height: 8),
              _CheckRow(
                ok: true,
                title: 'Code: $code',
                detail: 'Checked against earlier sales when you record it.',
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DesignColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              ),
              child: Text(
                _isMpesa
                    ? 'Check your own M-Pesa first. Messages can be faked. Open your till statement and look for this code before you hand over the goods.'
                    : 'Check your bank account first. Look for this payment in your own statement before you hand over the goods.',
                style: TextStyle(color: palette.ink, fontSize: 12.5, height: 1.45),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _seenInAccount = !_seenInAccount;
                        _error = null;
                      }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _seenInAccount,
                      activeColor: DesignColors.accent,
                      checkColor: SignInPalette.onAccent,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                                _seenInAccount = value ?? false;
                                _error = null;
                              }),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _isMpesa
                              ? 'I have seen this payment in my own M-Pesa. Recorded by $recorderName.'
                              : 'I have seen this payment in my bank account. Recorded by $recorderName.',
                          style: TextStyle(
                              color: palette.ink, fontSize: 13.5, height: 1.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_needsApproval) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.themed(DesignColors.accentSubtle),
                  borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                ),
                child: Text(
                  'This payment is over ${formatKes(widget.rules.approvalLimit)}. A manager or the owner must approve it with their PIN. Both names are saved on the sale.',
                  style: TextStyle(color: palette.ink, fontSize: 12.5, height: 1.45),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                onChanged: (_) => setState(() => _error = null),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration:
                    const InputDecoration(labelText: 'Manager or owner PIN'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              SignInError(message: _error!),
            ],
            const SizedBox(height: 16),
            SignInButton(
              label: 'Record and complete sale',
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.ok,
    required this.title,
    required this.detail,
    this.warn = false,
  });

  final bool ok;
  final bool warn;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final color = ok
        ? DesignColors.success
        : warn
            ? DesignColors.warning
            : DesignColors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(
            ok ? Icons.check_rounded : Icons.priority_high_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: palette.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              Text(detail, style: TextStyle(color: palette.soft, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

