import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:axon_pos/core/di/injection.dart';
import 'package:axon_pos/core/network/api_client.dart';
import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/core/utils/api_message.dart';
import 'package:axon_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:axon_pos/features/auth/presentation/widgets/sign_in_kit.dart';

/// Computer sign-in by a phone that is already signed in.
///
/// The computer makes a random verifier and keeps it in memory. Only its
/// SHA-256 goes to the server, so the QR and code on screen cannot be used
/// to take the sign-in from somewhere else.
class PhoneSignInScreen extends ConsumerStatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  ConsumerState<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

enum _Phase { starting, waiting, signingIn, refused, failed }

class _PhoneSignInScreenState extends ConsumerState<PhoneSignInScreen> {
  static final _random = Random.secure();

  _Phase _phase = _Phase.starting;
  String? _linkId;
  String? _verifier;
  String _qr = '';
  String _code = '';
  DateTime? _expiresAt;
  String? _message;
  Timer? _poll;
  Timer? _clock;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _phase != _Phase.waiting) return;
      // Renew on this computer's own clock as well, so a code never stays
      // on screen past its time when the status checks are not getting
      // through. The grace lets a last-second approval arrive first.
      final expiresAt = _expiresAt;
      if (expiresAt != null &&
          !_checking &&
          DateTime.now().isAfter(expiresAt.add(const Duration(seconds: 4)))) {
        _start();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  static String _newVerifier() => base64Url
      .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  String get _computerName {
    try {
      final name = Platform.localHostname.trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'This computer';
  }

  Future<void> _start() async {
    _poll?.cancel();
    final verifier = _newVerifier();
    setState(() {
      _phase = _Phase.starting;
      _message = null;
    });
    try {
      final started = await getIt<ApiClient>().startDesktopLink(
        desktopName: _computerName,
        platform: Platform.operatingSystem,
        claimChallenge: sha256.convert(utf8.encode(verifier)).toString(),
      );
      if (!mounted) return;
      setState(() {
        _verifier = verifier;
        _linkId = started['linkId']?.toString();
        _qr = started['qr']?.toString() ?? '';
        _code = started['code']?.toString() ?? '';
        // Counted on this computer's clock, which may not match the service.
        final lasts = num.tryParse(started['expiresIn']?.toString() ?? '');
        _expiresAt = lasts != null
            ? DateTime.now().add(Duration(seconds: lasts.round()))
            : DateTime.tryParse(started['expiresAt']?.toString() ?? '')?.toLocal();
        _phase = _Phase.waiting;
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _message = apiErrorMessage(e);
      });
    }
  }

  Future<void> _check() async {
    final linkId = _linkId;
    if (_checking || linkId == null || _phase != _Phase.waiting) return;
    _checking = true;
    try {
      final status = await getIt<ApiClient>().desktopLinkStatus(linkId);
      if (!mounted) return;
      switch (status['status']) {
        case 'approved':
          await _finish();
        case 'denied':
          _poll?.cancel();
          setState(() => _phase = _Phase.refused);
        case 'expired':
        case 'claimed':
          // A fresh code replaces the old one, like a messaging app's QR.
          await _start();
      }
    } catch (_) {
      // A missed poll is retried two seconds later.
    } finally {
      _checking = false;
    }
  }

  Future<void> _finish() async {
    _poll?.cancel();
    setState(() => _phase = _Phase.signingIn);
    final ok = await ref.read(authControllerProvider.notifier).loginWithLinkedPhone(
          linkId: _linkId!,
          verifier: _verifier!,
        );
    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      setState(() {
        _phase = _Phase.failed;
        _message = ref.read(authControllerProvider).error ??
            'The sign-in did not finish. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        title: const Text('Sign in with your phone'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Wrap(
                spacing: 48,
                runSpacing: 32,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: 300, child: _codePanel(palette)),
                  SizedBox(width: 380, child: _steps(palette)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _codePanel(SignInPalette palette) {
    switch (_phase) {
      case _Phase.starting:
      case _Phase.signingIn:
        return SizedBox(
          height: 300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: DesignColors.accent),
              const SizedBox(height: DesignSpacing.md),
              Text(
                _phase == _Phase.signingIn ? 'Approved. Opening your shop…' : 'Getting a code…',
                style: TextStyle(color: palette.soft),
              ),
            ],
          ),
        );
      case _Phase.refused:
      case _Phase.failed:
        return Column(
          children: [
            Icon(
              _phase == _Phase.refused ? Icons.block_rounded : Icons.wifi_off_rounded,
              size: 52,
              color: _phase == _Phase.refused ? DesignColors.error : DesignColors.warning,
            ),
            const SizedBox(height: DesignSpacing.md),
            Text(
              _phase == _Phase.refused
                  ? 'The phone refused this sign-in.'
                  : (_message ?? 'Something went wrong.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.ink, height: 1.4),
            ),
            const SizedBox(height: DesignSpacing.lg),
            SignInButton(label: 'Show a new code', onPressed: _start),
          ],
        );
      case _Phase.waiting:
        final left =
            _expiresAt?.difference(DateTime.now()).inSeconds.clamp(0, 999);
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
                border: Border.all(color: palette.line),
              ),
              child: QrImageView(
                data: _qr,
                size: 260,
                backgroundColor: Colors.white,
                semanticsLabel: 'Sign-in code for your phone to scan',
              ),
            ),
            const SizedBox(height: DesignSpacing.md),
            SelectableText(
              _code.length == 6 ? '${_code.substring(0, 3)} ${_code.substring(3)}' : _code,
              style: DesignType.display.copyWith(
                fontSize: 30,
                letterSpacing: 6,
                color: palette.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              left == null ? '' : 'New code in ${left}s',
              style: TextStyle(color: palette.faint, fontSize: 12),
            ),
          ],
        );
    }
  }

  Widget _steps(SignInPalette palette) {
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: DesignSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text('$n',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: DesignColors.accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: TextStyle(color: palette.ink, height: 1.45)),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Open your shop on this computer',
          style: DesignType.display.copyWith(fontSize: 24, color: palette.ink),
        ),
        const SizedBox(height: DesignSpacing.sm),
        Text(
          'Use a phone that is already signed in to Counterbase. No password is typed here.',
          style: TextStyle(color: palette.soft, height: 1.45),
        ),
        const SizedBox(height: DesignSpacing.lg),
        step(1, 'On your phone, open Counterbase, then Settings and Sign in a computer.'),
        step(2, 'Scan this code, or type the 6 digits under it.'),
        step(3, 'Check the computer name on your phone and tap Sign it in.'),
        const SizedBox(height: DesignSpacing.sm),
        Text(
          'This computer opens with the same account and role as the phone that approves it.',
          style: TextStyle(color: palette.faint, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}
