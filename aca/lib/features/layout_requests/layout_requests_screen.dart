import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';

/// One shop's request to change its business type, with the reason it gave.
class LayoutRequest {
  LayoutRequest({
    required this.id,
    required this.tenantName,
    required this.tenantSlug,
    required this.fromProfileId,
    required this.toProfileId,
    required this.reason,
    required this.status,
    required this.decisionNote,
    required this.createdAt,
  });

  final String id;
  final String tenantName;
  final String? tenantSlug;
  final String? fromProfileId;
  final String toProfileId;
  final String reason;
  final String status; // PENDING | APPROVED | REJECTED | CANCELLED
  final String? decisionNote;
  final DateTime? createdAt;

  bool get pending => status == 'PENDING';

  factory LayoutRequest.fromJson(Map<String, dynamic> j) {
    final tenant = J.map(j['tenant']);
    return LayoutRequest(
      id: J.s(j['id']),
      tenantName: J.s(tenant['name'], 'Company'),
      tenantSlug: J.sn(tenant['slug']),
      fromProfileId: J.sn(j['fromProfileId']),
      toProfileId: J.s(j['toProfileId']),
      reason: J.s(j['reason']),
      status: J.s(j['status'], 'PENDING'),
      decisionNote: J.sn(j['decisionNote']),
      createdAt: J.d(j['createdAt']),
    );
  }
}

String layoutProfileLabel(String? id) =>
    id == null || id.isEmpty ? 'Not chosen yet' : Fmt.label(id.replaceAll('_', ' '));

Tone layoutRequestTone(String status) {
  switch (status) {
    case 'APPROVED':
      return Tone.success;
    case 'REJECTED':
      return Tone.danger;
    case 'CANCELLED':
      return Tone.neutral;
    default:
      return Tone.warning;
  }
}

Future<List<LayoutRequest>> _load(AcaRepository repo, String status) async {
  final json = await repo.api.getMap('/layout-requests', query: {'status': status.isEmpty ? null : status});
  return J.list(json['items']).map(LayoutRequest.fromJson).toList();
}

/// Business type change requests from shops. A paid shop is locked to the
/// business type it paid for, so a change comes here for a person to approve.
class LayoutRequestsScreen extends StatefulWidget {
  const LayoutRequestsScreen({super.key});

  @override
  State<LayoutRequestsScreen> createState() => _LayoutRequestsScreenState();
}

class _LayoutRequestsScreenState extends State<LayoutRequestsScreen> {
  String _status = 'PENDING';
  final _key = GlobalKey<LoadBuilderState<List<LayoutRequest>>>();

  static const _filters = <String, String>{
    'PENDING': 'Waiting',
    'APPROVED': 'Approved',
    'REJECTED': 'Declined',
    '': 'All',
  };

  Future<void> _decide(LayoutRequest request, bool approve, Future<void> Function() reload) async {
    final repo = context.read<AcaRepository>();
    final note = await promptText(
      context,
      title: approve ? 'Approve change' : 'Decline change',
      label: approve ? 'Note to the owner (optional)' : 'Why is it declined?',
      message: approve
          ? '${request.tenantName} will be able to switch to ${layoutProfileLabel(request.toProfileId)} from Layout actions.'
          : 'The owner sees this reply. Suggest adding a store if that fits.',
      confirmLabel: approve ? 'Approve' : 'Decline',
      required: !approve,
      destructive: !approve,
    );
    if (note == null || !mounted) return;
    final ok = await runAction(
      context,
      () => repo.api.post('/layout-requests/${request.id}/decision', body: {'approve': approve, 'note': note}),
      success: approve ? 'Approved. The owner has been told.' : 'Declined. The owner has been told.',
    );
    if (ok) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final canDecide = context.select<SessionController, bool>((s) => s.can(Perm.tenantsManage));
    final repo = context.read<AcaRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Layout requests')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final entry in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _status == entry.key,
                      onSelected: (_) {
                        setState(() => _status = entry.key);
                        _key.currentState?.reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LoadBuilder<List<LayoutRequest>>(
              key: _key,
              load: () => _load(repo, _status),
              emptyWhen: (items) => items.isEmpty,
              empty: const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No requests here',
                message: 'When a shop asks to change its business type, it shows up here.',
              ),
              builder: (context, items, reload) => ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final r = items[i];
                  return AcaCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.tenantName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                            StatusPill(Fmt.label(r.status), tone: layoutRequestTone(r.status), dense: true),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusPill(layoutProfileLabel(r.fromProfileId), dense: true),
                            Icon(Icons.arrow_forward_rounded, size: 16, color: p.textFaint),
                            StatusPill(layoutProfileLabel(r.toProfileId), tone: Tone.brand, dense: true),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('"${r.reason}"', style: TextStyle(color: p.text, height: 1.4)),
                        const SizedBox(height: 6),
                        Text(
                          'Sent ${Fmt.ago(r.createdAt)}',
                          style: TextStyle(color: p.textMuted, fontSize: 12.5),
                        ),
                        if (r.decisionNote != null && r.decisionNote!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Reply: ${r.decisionNote}', style: TextStyle(color: p.textMuted, fontSize: 12.5)),
                        ],
                        if (r.pending && canDecide) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _decide(r, false, reload),
                                  child: const Text('Decline'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => _decide(r, true, reload),
                                  child: const Text('Approve'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
