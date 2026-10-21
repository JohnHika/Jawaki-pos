import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'account_logic.dart';
import 'backup_codes_screen.dart';
import 'sheet_kit.dart';

/// Full-screen "turn on two-step verification" flow: scan the QR code (or type the
/// key), confirm with a 6-digit code, then save the backup codes.
/// Pops with true once two-step verification is on.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  final _code = TextEditingController();
  TwoFactorSetup? _setup;
  Object? _loadError;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  // The server issues a fresh secret on every call, so this runs once per visit
  // (and again only when the person taps "Try again").
  Future<void> _start() async {
    final repo = context.read<AcaRepository>();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await repo.startTwoFactorSetup();
      if (!mounted) return;
      setState(() {
        _setup = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _enable() async {
    if (!isSixDigitCode(_code.text) || _busy) return;
    final repo = context.read<AcaRepository>();
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    List<String> codes;
    try {
      codes = await repo.enableTwoFactor(cleanOtp(_code.text));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
      return;
    }
    // Two-step verification is on at this point; refresh the profile so the rest of the app knows.
    await session.reloadProfile();
    if (!mounted) return;
    setState(() => _busy = false);
    if (codes.isNotEmpty) {
      await nav.push<bool>(MaterialPageRoute<bool>(builder: (_) => BackupCodesScreen(codes: codes)));
    }
    if (mounted) nav.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Two-step verification')),
        body: _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final setup = _setup;
    if (setup == null) {
      return ErrorState(error: _loadError ?? 'Could not start setup', onRetry: _start);
    }
    final p = context.aca;
    final ready = isSixDigitCode(_code.text);
    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _StepTitle(number: 1, text: 'Scan this QR code'),
        const SizedBox(height: 6),
        Text(
          'Open an authenticator app such as Google Authenticator, Microsoft Authenticator or Authy, '
          'add a new account and scan the code below.',
          style: TextStyle(color: p.textMuted, height: 1.45),
        ),
        const SizedBox(height: 14),
        Center(child: _QrCard(data: setup.otpauthUri)),
        const SizedBox(height: 18),
        AcaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Can\'t scan? Enter this key', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('Choose "Enter a setup key" in your app, then type the key below.',
                  style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: SelectableText(
                  groupSecret(setup.secret),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    height: 1.5,
                    color: p.text,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CopyButton(text: rawSecret(setup.secret), label: 'Copy key', copiedLabel: 'Key copied'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _StepTitle(number: 2, text: 'Enter the 6-digit code'),
        const SizedBox(height: 6),
        Text(
          'Type the code your app shows for ACA. It changes every 30 seconds.',
          style: TextStyle(color: p.textMuted, height: 1.45),
        ),
        const SizedBox(height: 14),
        if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
        TextField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(7)],
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _enable(),
          decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
        ),
        const SizedBox(height: 16),
        SubmitButton(label: 'Turn on two-step verification', busy: _busy, onPressed: ready ? _enable : null),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.brand.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Text('$number', style: TextStyle(color: p.brand, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}

/// The QR code is always black on white, whatever the app theme: authenticator
/// apps cannot read inverted codes.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});
  final String data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'QR code for your authenticator app',
      image: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: QrImageView(
          data: data,
          size: 220,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
      ),
    );
  }
}
