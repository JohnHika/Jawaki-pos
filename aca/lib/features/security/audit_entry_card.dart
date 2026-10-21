import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import 'security_logic.dart';

/// One audit entry as a tappable card: category icon tinted by severity,
/// headline, who did it, a severity pill for warnings / critical events and
/// when it happened (relative, with the exact time beside it).
class AuditEntryCard extends StatelessWidget {
  const AuditEntryCard({super.key, required this.entry, required this.onTap, this.bottomPadding = 8});

  final AuditEntry entry;
  final VoidCallback onTap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final tone = severityTone(entry.severity);
    final iconColor = tone == Tone.neutral ? p.textMuted : p.toneColor(tone);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: AcaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(12)),
              child: Icon(categoryIcon(entry.category), size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entryTitle(entry),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    actorLine(entry),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showSeverityPill(entry.severity))
                        StatusPill(severityLabel(entry.severity), tone: tone, dense: true),
                      Text(
                        Fmt.ago(entry.createdAt),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textMuted),
                      ),
                      Text(
                        Fmt.dateTime(entry.createdAt),
                        style: TextStyle(fontSize: 12, color: p.textFaint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
