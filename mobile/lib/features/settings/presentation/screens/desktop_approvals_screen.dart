import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/design_system.dart';

/// In-app surface for desktop sign-in requests: a live list of pending
/// pairings with approve / deny. Reached from the sign-in notification or
/// Settings → Desktop sign-ins.
class DesktopApprovalsScreen extends ConsumerStatefulWidget {
  const DesktopApprovalsScreen({super.key});

  @override
  ConsumerState<DesktopApprovalsScreen> createState() =>
      _DesktopApprovalsScreenState();
}

class _DesktopApprovalsScreenState
    extends ConsumerState<DesktopApprovalsScreen> {
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _pending = const [];
  String? _error;
  String? _busyCode;

  @override
  void initState() {
    super.initState();
    _refresh();
    // The list is short-lived by design (3-minute challenges); poll while open.
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final pending = await getIt<ApiClient>().getPendingDesktopLinks();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load sign-in requests.');
    }
  }

  Future<void> _decide({
    required String code,
    required String decision,
  }) async {
    setState(() => _busyCode = code);
    try {
      await getIt<ApiClient>().decideDesktopLink(
        code: code,
        approve: decision == 'approve',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approve'
                ? 'Desktop approved — it will sign in now'
                : 'Desktop sign-in denied',
          ),
        ),
      );
      await _refresh();
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          (e.response?.data is Map ? e.response?.data['message'] : null) ??
              'The request failed — it may have expired on the desktop.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message.toString())),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _busyCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const fg = DesignColors.textPrimary;
    return Scaffold(
      backgroundColor: DesignColors.darkBg,
      appBar: AppBar(
        backgroundColor: DesignColors.darkBg,
        foregroundColor: fg,
        title: const Text('Desktop sign-ins'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DesignSpacing.lg),
          children: [
            Text(
              'APPROVE A COMPUTER',
              style: TextStyle(
                color: fg.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'When a laptop shows a QR code, confirm the 6-digit code here '
              'to sign it in — no passwords on shared computers.',
              style: TextStyle(color: fg.withValues(alpha: 0.7), height: 1.4),
            ),
            const SizedBox(height: DesignSpacing.lg),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(DesignSpacing.md),
                decoration: BoxDecoration(
                  color: DesignColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: DesignColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: DesignColors.error),
                ),
              ),
              const SizedBox(height: DesignSpacing.lg),
            ],
            if (_pending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(Icons.devices_rounded,
                        size: 44, color: fg.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'No waiting sign-in requests',
                      style: TextStyle(color: fg.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Requests appear here when a desktop shows its QR code.',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final request in _pending)
                _RequestCard(
                  request: request,
                  busy: _busyCode == request['code'],
                  onApprove: () => _decide(
                    code: request['code'].toString(),
                    decision: 'approve',
                  ),
                  onDeny: () => _decide(
                    code: request['code'].toString(),
                    decision: 'deny',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDeny,
  });

  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final desktopName =
        (request['desktopName'] as String?)?.trim().isNotEmpty == true
            ? request['desktopName'] as String
            : 'A computer';
    final code = request['code'].toString();
    return Container(
      margin: const EdgeInsets.only(bottom: DesignSpacing.md),
      padding: const EdgeInsets.all(DesignSpacing.md),
      decoration: BoxDecoration(
        color: DesignColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DesignColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: DesignColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.laptop_windows_rounded,
                    color: DesignColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desktopName,
                      style: const TextStyle(
                        color: DesignColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'wants to sign in to this shop',
                      style: TextStyle(
                        color:
                            DesignColors.textPrimary.withValues(alpha: 0.6),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: DesignColors.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'MATCH THIS CODE',
                  style: TextStyle(
                    color:
                        DesignColors.textPrimary.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  code,
                  style: const TextStyle(
                    color: DesignColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDeny,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DesignColors.error,
                    side: BorderSide(
                      color: DesignColors.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: busy ? null : onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: DesignColors.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
