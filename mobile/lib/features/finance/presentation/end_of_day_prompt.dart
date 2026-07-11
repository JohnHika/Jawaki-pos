import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/di/injection.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/design_system.dart';

/// Foreground "close the day?" prompt. Shown when an authorized user is in
/// the app past the branch's configured closing time and today hasn't been
/// closed yet. Deliberately lightweight — no background/cron infra; the
/// close happens when someone's actually present, which is when it should.
///
/// Call [maybePrompt] on app open and on resume (from the dashboard). It
/// self-gates on permission, closing time, close status, and a once-per-day
/// in-memory flag so it never nags repeatedly in one session.
class EndOfDayPrompt {
  EndOfDayPrompt._();

  // Which calendar day we've already prompted for this session, so resuming
  // the app repeatedly after close time doesn't re-nag.
  static String? _promptedForDay;

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static const _dayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

  static Future<void> maybePrompt(
    BuildContext context,
    RolePermissions permissions,
  ) async {
    // 1. Permission gate — only users who can close should be asked.
    if (!permissions.canCloseEndOfDay) return;

    final branchId = getIt<AuthService>().branchId;
    if (branchId == null) return;

    final today = _todayIso();
    if (_promptedForDay == today) return; // already handled this session

    final api = getIt<ApiClient>();

    // 2. Is it past today's configured closing time?
    Map<String, dynamic> branch;
    try {
      branch = await api.getBranch(branchId);
    } catch (_) {
      return; // can't tell without hours; stay silent
    }
    final settings = (branch['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final hours = (settings['operatingHours'] as Map?)?.cast<String, dynamic>();
    if (hours == null) return; // no hours configured -> no close-time prompt

    final days = (hours['days'] as Map?)?.cast<String, dynamic>() ?? {};
    final now = DateTime.now();
    final todayKey = _dayKeys[now.weekday % 7]; // DateTime.weekday: Mon=1..Sun=7
    final day = (days[todayKey] as Map?)?.cast<String, dynamic>();
    if (day == null || day['closed'] == true) return; // closed day -> nothing to close-prompt
    final closeStr = (day['close'] ?? '').toString();
    final parts = closeStr.split(':');
    if (parts.length != 2) return;
    final closeMinutes = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    final nowMinutes = now.hour * 60 + now.minute;
    if (nowMinutes < closeMinutes) return; // not closing time yet

    // 3. Already closed today? Then don't ask.
    try {
      final existing = await api.getDailyClose(branchId, date: today);
      if (existing != null) {
        _promptedForDay = today; // treat as handled
        return;
      }
    } catch (_) {
      // If we can't confirm, err toward not nagging.
      return;
    }

    if (!context.mounted) return;
    _promptedForDay = today; // mark handled regardless of the user's choice

    final goClose = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_available_rounded, color: DesignColors.accent),
        title: const Text('Close the day?'),
        content: const Text(
          "You're past today's closing time and the day hasn't been closed yet. "
          "Close it now to finalize the sales summary and count the till, or do it later.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Close day'),
          ),
        ],
      ),
    );

    if (goClose == true && context.mounted) {
      context.push('/cash-flow/end-of-day');
    }
  }
}
