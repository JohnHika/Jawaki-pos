import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import 'account_logic.dart';

/// One signed-in device: label, IP and when it was last used. Used on the
/// Account screen (with a sign-out menu) and on a staff member's page.
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, this.trailing});

  final SessionInfo session;

  /// e.g. a "sign out this device" menu.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return AcaCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      tone: session.current ? Tone.brand : null,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.smartphone_rounded, color: session.current ? p.brand : p.textMuted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        deviceTitle(session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (session.current) ...[
                      const SizedBox(width: 8),
                      const StatusPill('This device', tone: Tone.brand, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  sessionSubtitle(session),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textMuted, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox(width: 8),
        ],
      ),
    );
  }
}
