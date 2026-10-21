import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/widgets/brand.dart';
import '../../state/session.dart';

/// Opaque screen shown over the app while it is locked (after the app was in the
/// background, or on cold start). Authenticates with the phone's biometrics or
/// screen lock; nothing behind it is rendered.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _trying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_trying) return;
    setState(() => _trying = true);
    await context.read<SessionController>().unlock();
    if (mounted) setState(() => _trying = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const AcaLockup(),
              const SizedBox(height: 28),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: p.textMuted),
                const SizedBox(width: 8),
                Text('ACA is locked', style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600)),
              ]),
              const Spacer(flex: 3),
              FilledButton.icon(
                onPressed: _trying ? null : _unlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.read<SessionController>().signOut(),
                child: const Text('Sign out instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen status shown while the app boots or cannot reach the server.
class BootScreen extends StatelessWidget {
  const BootScreen({super.key, this.error, this.onRetry});
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AcaLockup(),
                const SizedBox(height: 36),
                if (error == null)
                  SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: p.brand))
                else ...[
                  Icon(Icons.cloud_off_rounded, color: p.textMuted, size: 32),
                  const SizedBox(height: 10),
                  Text(error!, textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, height: 1.4)),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(160, 46)),
                    child: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: () => context.read<SessionController>().signOut(remote: false),
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
