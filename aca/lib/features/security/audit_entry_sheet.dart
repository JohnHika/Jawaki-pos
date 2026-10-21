import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../state/session.dart';
import '../billing/sheet_parts.dart';
import '../team/staff_detail_screen.dart';
import '../tenants/tenant_detail_screen.dart';
import 'security_logic.dart';

/// Opens the detail sheet for one audit entry: what happened, who did it,
/// when, from where, what it touched and the recorded details.
///
/// Used by the Audit log and by the Security centre's "Recent alerts".
/// [showActorLink] / [showCompanyLink] hide the "Open staff member" / "Open
/// company" shortcuts where they would only lead back to the screen the user
/// came from.
Future<void> showAuditEntrySheet(
  BuildContext context,
  AuditEntry entry, {
  bool showActorLink = true,
  bool showCompanyLink = true,
}) {
  return showDetailSheet<void>(
    context,
    builder: (_) => _AuditEntrySheet(entry: entry, showActorLink: showActorLink, showCompanyLink: showCompanyLink),
  );
}

class _AuditEntrySheet extends StatelessWidget {
  const _AuditEntrySheet({required this.entry, required this.showActorLink, required this.showCompanyLink});

  final AuditEntry entry;
  final bool showActorLink;
  final bool showCompanyLink;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final session = context.watch<SessionController>();
    final tone = severityTone(entry.severity);
    final title = prettifyAction(entry.action);
    final summary = entry.summary?.trim();
    final device = trimUserAgent(entry.userAgent);
    final meta = flattenMetadata(entry.metadata);
    final hasTarget = (entry.targetType?.isNotEmpty ?? false) || (entry.targetId?.isNotEmpty ?? false);
    final tenantId = entry.tenantId;
    final canOpenCompany =
        showCompanyLink && session.can(Perm.tenantsView) && tenantId != null && tenantId.isNotEmpty;
    final actorId = entry.actorId;
    final canOpenActor = showActorLink && session.can(Perm.teamView) && actorId != null && actorId.isNotEmpty;
    final role = entry.actorRole;

    return DetailSheetBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(12)),
              child: Icon(categoryIcon(entry.category), color: tone == Tone.neutral ? p.textMuted : p.toneColor(tone)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusPill(categoryLabel(entry.category), dense: true),
                      if (showSeverityPill(entry.severity))
                        StatusPill(severityLabel(entry.severity), tone: tone, dense: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(summary, style: TextStyle(color: p.text, height: 1.4, fontSize: 15)),
        ],
        const SheetSectionTitle('What'),
        DetailRow('Action', title),
        const DetailDivider(),
        DetailRow('Code', entry.action, mono: true, muted: true, copyText: entry.action, copyLabel: 'Action code copied'),
        const SheetSectionTitle('Who'),
        DetailRow('Staff member', entry.actorEmail, copyText: entry.actorEmail, copyLabel: 'Email copied'),
        const DetailDivider(),
        DetailRow(
          'Role',
          null,
          valueWidget: role == null || role.isEmpty
              ? const Text('—', style: TextStyle(fontWeight: FontWeight.w600))
              : StatusPill(Fmt.label(role), tone: StatusTone.role(role), dense: true),
        ),
        const SheetSectionTitle('When'),
        DetailRow('Time', entry.createdAt == null ? null : Fmt.dateTime(entry.createdAt)),
        const DetailDivider(),
        DetailRow('Ago', Fmt.ago(entry.createdAt)),
        const SheetSectionTitle('Where'),
        DetailRow('IP address', entry.ipAddress, mono: true, copyText: entry.ipAddress, copyLabel: 'IP address copied'),
        const DetailDivider(),
        DetailRow('Device', device),
        if (hasTarget) ...[
          const SheetSectionTitle('Target'),
          DetailRow('Type', prettifyTargetType(entry.targetType)),
          const DetailDivider(),
          DetailRow(
            'Reference',
            entry.targetId,
            mono: true,
            muted: true,
            copyText: entry.targetId,
            copyLabel: 'Target ID copied',
          ),
        ],
        if (meta.isNotEmpty) ...[
          const SheetSectionTitle('Details'),
          for (var i = 0; i < meta.length; i++) ...[
            if (i > 0) const DetailDivider(),
            DetailRow(meta[i].label, meta[i].value),
          ],
        ],
        if (canOpenCompany || canOpenActor) const SizedBox(height: 20),
        if (canOpenCompany)
          OutlinedButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute<void>(builder: (_) => TenantDetailScreen(tenantId: tenantId)));
            },
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Open company'),
          ),
        if (canOpenCompany && canOpenActor) const SizedBox(height: 10),
        if (canOpenActor)
          OutlinedButton.icon(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(
                MaterialPageRoute<void>(
                  builder: (_) => StaffDetailScreen(staffId: actorId, name: entry.actorEmail),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Open staff member'),
          ),
      ],
    );
  }
}
