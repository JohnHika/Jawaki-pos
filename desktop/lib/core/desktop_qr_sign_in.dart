import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/counterbase_theme.dart';
import 'desktop_link_client.dart';
import 'desktop_workspace.dart';

/// Sign in with the shop's phone: the desktop shows a QR (plus a 6-digit
/// fallback code), an approved phone user confirms, and this workspace
/// adopts the session. Replaces typing the owner PIN.
class DesktopQrSignIn extends StatefulWidget {
  const DesktopQrSignIn({
    super.key,
    required this.session,
    required this.phoneBaseUrl,
    this.onBack,
    this.onLinked,
  });

  final DesktopSession session;

  /// Phone-server base URL, e.g. `http://192.168.1.20:3000`.
  final String phoneBaseUrl;

  final VoidCallback? onBack;

  /// Called with the claimed session after the phone approves.
  final void Function(DesktopLinkSession session)? onLinked;

  @override
  State<DesktopQrSignIn> createState() => _DesktopQrSignInState();
}

class _DesktopQrSignInState extends State<DesktopQrSignIn> {
  late DesktopLinkClient _client;
  Timer? _pollTimer;
  DesktopLinkStart? _start;
  String? _error;
  bool _busy = true;
  bool _finishing = false;
  bool _pollInFlight = false;

  @override
  void initState() {
    super.initState();
    _client = DesktopLinkClient(baseUrlOverride: widget.phoneBaseUrl);
    _begin();
  }

  @override
  void didUpdateWidget(covariant DesktopQrSignIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phoneBaseUrl != widget.phoneBaseUrl) {
      _pollTimer?.cancel();
      _client = DesktopLinkClient(baseUrlOverride: widget.phoneBaseUrl);
      _start = null;
      _finishing = false;
      _begin();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _busy = true;
      _error = null;
      _start = null;
    });
    try {
      final start = await _client.start(desktopName: _deviceLabel());
      if (!mounted) return;
      setState(() => _start = start);
      _schedulePoll();
    } on DesktopLinkFailure catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _deviceLabel() {
    final business = widget.session.businessName;
    return business == 'Counterbase' ? 'Counterbase desktop' : business;
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final start = _start;
      if (start == null || _finishing || !mounted) return;

      // Expired locally: regenerate without waiting for the server round trip.
      if (DateTime.now().isAfter(start.expiresAt)) {
        await _begin();
        return;
      }

      final DesktopLinkStatus status;
      try {
        status = await _client.status(start.linkId);
      } on DesktopLinkFailure {
        // Transient network hiccup — keep the QR up; the next tick retries.
        return;
      }
      if (!mounted) return;

      switch (status.status) {
        case 'approved':
          await _finishClaim(start);
        case 'denied':
          _pollTimer?.cancel();
          setState(() {
            _error =
                'The sign-in was denied on the phone. Scan again to retry.';
          });
        case 'claimed':
          _pollTimer?.cancel();
          setState(() {
            _error = 'That sign-in was already used. Starting a new one…';
          });
          await _begin();
        case 'expired':
          await _begin();
        default:
          break;
      }
    } finally {
      _pollInFlight = false;
    }
  }

  Future<void> _finishClaim(DesktopLinkStart start) async {
    _pollTimer?.cancel();
    setState(() => _finishing = true);
    try {
      final secret = start.secret;
      if (secret == null || secret.isEmpty) {
        throw const DesktopLinkFailure(
          'The QR payload was incomplete. Start a new sign-in.',
        );
      }
      final session = await _client.claim(linkId: start.linkId, secret: secret);
      if (!mounted) return;
      widget.onLinked?.call(session);
    } on DesktopLinkFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _finishing = false;
      });
      await _begin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbTag('SIGN IN WITH YOUR PHONE'),
        const SizedBox(height: 12),
        Text(
          'Approve on your phone',
          style: CbText.display.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 10),
        Text(
          'Open Counterbase on the phone, then scan this code — or tap the '
          'sign-in request in the app — to unlock this computer.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        Center(child: _buildQrPanel(context)),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CbInk.error),
          ),
          const SizedBox(height: 12),
        ],
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : () => widget.onBack?.call(),
            icon: const Icon(Icons.keyboard_rounded, size: 18),
            label: const Text('Use owner PIN instead'),
          ),
        ),
      ],
    );
  }

  Widget _buildQrPanel(BuildContext context) {
    final start = _start;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CbInk.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CbInk.border),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 208,
            height: 208,
            child: _busy || start == null
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : _finishing
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, color: CbInk.ok, size: 44),
                      SizedBox(height: 10),
                      Text(
                        'Approved — signing in…',
                        style: TextStyle(
                          color: CbInk.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : QrImageView(
                    data: start.qr,
                    version: QrVersions.auto,
                    size: 208,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0B0A0F),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0B0A0F),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (start != null) ...[
            Text('OR ENTER THIS CODE ON THE PHONE', style: CbText.tag),
            const SizedBox(height: 6),
            Text(
              start.code,
              style: CbText.data.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                color: CbInk.text,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_iphone_rounded,
                size: 15,
                color: CbInk.muted,
              ),
              const SizedBox(width: 6),
              Text(
                'Waiting for approval — code refreshes every 3 minutes',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
