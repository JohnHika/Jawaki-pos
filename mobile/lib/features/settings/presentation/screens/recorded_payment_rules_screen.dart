import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/services/auth_service.dart';
import 'package:axon_pos/core/services/storage_service.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';
import 'package:axon_pos/features/sales/domain/recorded_payment.dart';

/// The shop's rules for payments it records itself, such as M-Pesa paid to its
/// own till or a bank transfer. Only the owner can change them.
class RecordedPaymentRulesScreen extends StatefulWidget {
  const RecordedPaymentRulesScreen({super.key});

  @override
  State<RecordedPaymentRulesScreen> createState() =>
      _RecordedPaymentRulesScreenState();
}

class _RecordedPaymentRulesScreenState
    extends State<RecordedPaymentRulesScreen> {
  late RecordedPaymentRules _rules;
  final _limitController = TextEditingController();
  final _tillController = TextEditingController();
  bool _saved = false;

  bool get _isOwner => getIt<AuthService>().isLocalWorkspaceOwner;

  @override
  void initState() {
    super.initState();
    _rules = const RecordedPaymentRules();
    final json = getIt<StorageService>().getRecordedPaymentRulesJson();
    if (json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) {
          _rules = RecordedPaymentRules.fromJson(decoded);
        }
      } catch (_) {
        // A damaged setting falls back to the safe defaults.
      }
    }
    _limitController.text = _rules.approvalLimit.round().toString();
    _tillController.text = _rules.tillNumber;
  }

  @override
  void dispose() {
    _limitController.dispose();
    _tillController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limit = double.tryParse(_limitController.text.trim());
    final next = _rules.copyWith(
      approvalLimit: limit != null && limit >= 0 ? limit : _rules.approvalLimit,
      tillNumber: _tillController.text.trim(),
    );
    await getIt<StorageService>()
        .saveRecordedPaymentRulesJson(jsonEncode(next.toJson()));
    if (!mounted) return;
    setState(() {
      _rules = next;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
        title: Text(
          'Recorded payments',
          style: DesignType.display.copyWith(
              color: palette.ink, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Money your customers send to your own till or bank can be recorded at checkout. Counterbase cannot check it with the bank, so these payments are marked "recorded" and follow your rules.',
                    style: TextStyle(color: palette.soft, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  if (!_isOwner)
                    const SignInError(
                      message: 'Only the owner can change these rules.',
                    ),
                  _RuleCard(
                    palette: palette,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: DesignColors.accent,
                      title: Text('Allow recorded payments',
                          style: TextStyle(
                              color: palette.ink, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        'Shows M-Pesa to our till and bank transfer at checkout.',
                        style: TextStyle(color: palette.soft, fontSize: 13),
                      ),
                      value: _rules.enabled,
                      onChanged: _isOwner
                          ? (value) {
                              setState(() {
                                _rules = _rules.copyWith(enabled: value);
                                _saved = false;
                              });
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RuleCard(
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('A manager must approve above',
                            style: TextStyle(
                                color: palette.ink, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'A recorded payment over this amount needs a manager or owner PIN. Enter 0 to need one every time.',
                          style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _limitController,
                          enabled: _isOwner,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onChanged: (_) => setState(() => _saved = false),
                          decoration: const InputDecoration(prefixText: 'KES '),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RuleCard(
                    palette: palette,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: DesignColors.accent,
                      title: Text('Require the pasted M-Pesa message',
                          style: TextStyle(
                              color: palette.ink, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        'Lets Counterbase read the code and amount, and refuse a message that does not match the sale.',
                        style: TextStyle(color: palette.soft, fontSize: 13),
                      ),
                      value: _rules.requireMessage,
                      onChanged: _isOwner
                          ? (value) {
                              setState(() {
                                _rules = _rules.copyWith(requireMessage: value);
                                _saved = false;
                              });
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RuleCard(
                    palette: palette,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your till, paybill or phone number',
                            style: TextStyle(
                                color: palette.ink, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'Shown at checkout so customers pay the right place.',
                          style: TextStyle(color: palette.soft, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _tillController,
                          enabled: _isOwner,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => setState(() => _saved = false),
                          decoration: const InputDecoration(hintText: '5 123 456'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A code can only be recorded once. Every recorded payment saves who recorded it, who approved it and the message that was pasted. Receipts and reports always say "recorded".',
                    style: TextStyle(color: palette.faint, fontSize: 12.5, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  SignInButton(
                    label: _saved ? 'Saved' : 'Save rules',
                    onPressed: _isOwner && !_saved ? _save : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.palette, required this.child});

  final SignInPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: palette.line),
        ),
        child: child,
      );
}
