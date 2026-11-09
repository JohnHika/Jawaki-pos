import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/utils/api_message.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../catalog/presentation/screens/barcode_scan_screen.dart';

/// Signs a computer in with this phone's account: scan the QR the computer
/// shows (or type its 6-digit code), check which computer is asking, then
/// approve. The computer never learns a password.
class DesktopApprovalsScreen extends ConsumerStatefulWidget {
  const DesktopApprovalsScreen({super.key});

  @override
  ConsumerState<DesktopApprovalsScreen> createState() =>
      _DesktopApprovalsScreenState();
}

enum _Step { find, confirm, approved, refused }

class _DesktopApprovalsScreenState
    extends ConsumerState<DesktopApprovalsScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  _Step _step = _Step.find;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _request;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            const BarcodeScanScreen(title: "Scan the computer's code"),
      ),
    );
    if (text == null || !mounted) return;
    // A typed or scanned 6-digit code works too.
    final digits = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^\d{6}$').hasMatch(digits)) {
      await _lookUp(code: digits);
    } else {
      await _lookUp(payload: text);
    }
  }

  Future<void> _lookUp({String? payload, String? code}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await getIt<ApiClient>()
          .previewDesktopLink(payload: payload, code: code);
      if (!mounted) return;
      setState(() {
        _request = request;
        _step = _Step.confirm;
      });
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide({required bool approve}) async {
    final request = _request;
    if (request == null) return;
    final pinRequired = request['pinRequired'] == true;
    if (approve && pinRequired && !RegExp(r'^\d{4,8}$').hasMatch(_pin.text)) {
      setState(() => _error = 'Enter your PIN to approve this computer.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await getIt<ApiClient>().decideDesktopLink(
        linkId: request['linkId'].toString(),
        approve: approve,
        pin: approve && pinRequired ? _pin.text : null,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _step = approve ? _Step.approved : _Step.refused);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startOver() {
    _code.clear();
    _pin.clear();
    setState(() {
      _request = null;
      _error = null;
      _step = _Step.find;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final auth = getIt<AuthService>();
    return Scaffold(
      backgroundColor: palette.page,
      appBar: AppBar(
        backgroundColor: palette.page,
        foregroundColor: palette.ink,
        title: const Text('Sign in a computer'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(DesignSpacing.lg),
              children: [
                if (auth.isLocalWorkspace)
                  _Note(
                    palette: palette,
                    text: 'This shop is kept on this phone only, so a '
                        'computer cannot sign in to it. Computers sign in '
                        'to shops that have an online account.',
                  )
                else
                  ...switch (_step) {
                    _Step.find => _find(palette),
                    _Step.confirm => _confirm(palette, auth),
                    _Step.approved => _finished(
                        palette,
                        icon: Icons.check_circle_rounded,
                        color: DesignColors.success,
                        title: 'Approved',
                        body:
                            '${_request?['desktopName'] ?? 'The computer'} is opening Counterbase with your account now.',
                      ),
                    _Step.refused => _finished(
                        palette,
                        icon: Icons.block_rounded,
                        color: DesignColors.error,
                        title: 'Refused',
                        body: 'The computer was not signed in.',
                      ),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _find(SignInPalette palette) => [
        Text(
          'On the computer, open Counterbase and choose Sign in with your '
          'phone. Then scan the code it shows.',
          style: TextStyle(color: palette.soft, height: 1.45),
        ),
        const SizedBox(height: DesignSpacing.lg),
        SignInButton(
          label: "Scan the computer's code",
          loading: _busy,
          onPressed: _busy ? null : _scan,
        ),
        const SizedBox(height: DesignSpacing.lg),
        Row(
          children: [
            Expanded(child: Divider(color: palette.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or type the 6-digit code',
                  style: TextStyle(color: palette.faint, fontSize: 12)),
            ),
            Expanded(child: Divider(color: palette.line)),
          ],
        ),
        const SizedBox(height: DesignSpacing.md),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: DesignType.display.copyWith(
            fontSize: 26,
            letterSpacing: 8,
            color: palette.ink,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(color: palette.faint, letterSpacing: 8),
            filled: true,
            fillColor: palette.field,
          ),
          onSubmitted: (_) => _lookUpCode(),
        ),
        const SizedBox(height: DesignSpacing.sm),
        SignInOutlineButton(
          label: 'Continue',
          onPressed: _busy ? null : _lookUpCode,
        ),
        if (_error != null) ...[
          const SizedBox(height: DesignSpacing.md),
          _Note(palette: palette, text: _error!, error: true),
        ],
      ];

  void _lookUpCode() {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Type all 6 digits shown on the computer.');
      return;
    }
    _lookUp(code: code);
  }

  List<Widget> _confirm(SignInPalette palette, AuthService auth) {
    final request = _request!;
    final name = request['desktopName']?.toString() ?? 'A computer';
    final platform = request['platform']?.toString();
    final place = request['place']?.toString();
    final sameNetwork = request['sameNetwork'] == true;
    final pinRequired = request['pinRequired'] == true;
    final user = auth.currentUser ?? const {};
    final person =
        '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final tenant = user['tenant'];
    final shop = tenant is Map ? tenant['name']?.toString() : null;

    return [
      Container(
        padding: const EdgeInsets.all(DesignSpacing.lg),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(DesignSpacing.radiusLg),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.desktop_windows_rounded,
                    color: DesignColors.accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: DesignType.display.copyWith(
                          fontSize: 20,
                          color: palette.ink,
                        ),
                      ),
                      Text(
                        [
                          if (platform != null) _platformLabel(platform),
                          if (place != null) place,
                        ].join(' · '),
                        style: TextStyle(color: palette.soft, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignSpacing.md),
            Text(
              'It will open ${shop ?? 'your shop'} as '
              '${person.isEmpty ? 'you' : person}, with everything your '
              'account can do.',
              style: TextStyle(color: palette.ink, height: 1.45),
            ),
          ],
        ),
      ),
      const SizedBox(height: DesignSpacing.md),
      _Note(
        palette: palette,
        error: !sameNetwork,
        icon: sameNetwork ? Icons.wifi_rounded : Icons.warning_amber_rounded,
        text: sameNetwork
            ? 'This computer is on the same internet connection as this phone.'
            : 'This computer is not on the same internet connection as this '
                "phone. Only approve if it is in front of you and you started "
                'the sign-in yourself.',
      ),
      if (pinRequired) ...[
        const SizedBox(height: DesignSpacing.md),
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Your PIN',
            counterText: '',
            filled: true,
            fillColor: palette.field,
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: DesignSpacing.md),
        _Note(palette: palette, text: _error!, error: true),
      ],
      const SizedBox(height: DesignSpacing.lg),
      SignInButton(
        label: 'Sign it in',
        loading: _busy,
        onPressed: _busy ? null : () => _decide(approve: true),
      ),
      const SizedBox(height: DesignSpacing.sm),
      SignInOutlineButton(
        label: "That's not me",
        onPressed: _busy ? null : () => _decide(approve: false),
      ),
    ];
  }

  List<Widget> _finished(
    SignInPalette palette, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) =>
      [
        const SizedBox(height: DesignSpacing.xl),
        Icon(icon, color: color, size: 56),
        const SizedBox(height: DesignSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: DesignType.display.copyWith(fontSize: 22, color: palette.ink),
        ),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.soft, height: 1.45)),
        const SizedBox(height: DesignSpacing.xl),
        SignInButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: DesignSpacing.sm),
        SignInOutlineButton(
          label: 'Sign in another computer',
          onPressed: _startOver,
        ),
      ];

  static String _platformLabel(String platform) => switch (platform) {
        'windows' => 'Windows',
        'macos' => 'Mac',
        'linux' => 'Linux',
        _ => platform,
      };
}

class _Note extends StatelessWidget {
  const _Note({
    required this.palette,
    required this.text,
    this.error = false,
    this.icon,
  });

  final SignInPalette palette;
  final String text;
  final bool error;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tone = error ? DesignColors.warning : DesignColors.success;
    return Container(
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? (error ? Icons.info_outline_rounded : Icons.check_rounded),
              color: tone, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: palette.ink, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
