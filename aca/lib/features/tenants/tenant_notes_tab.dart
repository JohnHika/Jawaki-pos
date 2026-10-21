import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/permissions.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/session.dart';
import 'tenant_widgets.dart';
import 'tenants_logic.dart';

/// Notes tab: internal notes about the company, pinned ones first.
class TenantNotesTab extends StatefulWidget {
  const TenantNotesTab({super.key, required this.tenantId, required this.refresh});

  final String tenantId;
  final Listenable refresh;

  @override
  State<TenantNotesTab> createState() => _TenantNotesTabState();
}

class _TenantNotesTabState extends State<TenantNotesTab> with TenantRefreshMixin {
  final _key = GlobalKey<LoadBuilderState<List<TenantNote>>>();

  @override
  Listenable get refreshSignal => widget.refresh;

  @override
  void onRefreshSignal() => _key.currentState?.reload();

  Future<void> _add(BuildContext context, Future<void> Function() reload) async {
    final repo = context.read<AcaRepository>();
    final draft = await showModalBottomSheet<NoteDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const NoteSheet(),
    );
    if (draft == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => repo.addTenantNote(widget.tenantId, draft.body, pinned: draft.pinned),
      success: 'Note added',
    );
    if (ok) await reload();
  }

  Future<void> _delete(BuildContext context, TenantNote note, Future<void> Function() reload) async {
    final repo = context.read<AcaRepository>();
    final yes = await confirmAction(
      context,
      title: 'Delete this note?',
      message: 'The note is removed for everyone on the team. This cannot be undone.',
      confirmLabel: 'Delete note',
      destructive: true,
    );
    if (!yes || !context.mounted) return;
    final ok = await runAction(context, () => repo.deleteTenantNote(widget.tenantId, note.id), success: 'Note deleted');
    if (ok) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AcaRepository>();
    final canManage = context.select<SessionController, bool>((s) => s.can(Perm.tenantsManage));

    return LoadBuilder<List<TenantNote>>(
      key: _key,
      load: () async => sortNotes(await repo.tenantNotes(widget.tenantId)),
      emptyWhen: (n) => n.isEmpty && !canManage,
      empty: const EmptyState(
        icon: Icons.sticky_note_2_outlined,
        title: 'No notes yet',
        message: 'Notes about this company will show up here.',
      ),
      builder: (context, notes, reload) {
        final p = context.aca;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: kTabPadding,
          children: [
            if (canManage)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  onPressed: () => _add(context, reload),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add note'),
                ),
              ),
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 36, color: p.textFaint),
                    const SizedBox(height: 10),
                    Text('No notes yet', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Write down anything the next person should know about this company.',
                        textAlign: TextAlign.center, style: TextStyle(color: p.textMuted, height: 1.4)),
                  ],
                ),
              ),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _NoteCard(note: n, canDelete: canManage, onDelete: () => _delete(context, n, reload)),
              ),
          ],
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.canDelete, required this.onDelete});

  final TenantNote note;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return AcaCard(
      tone: note.pinned ? Tone.brand : null,
      padding: EdgeInsets.fromLTRB(16, 14, canDelete ? 4 : 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.pinned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_rounded, size: 15, color: p.brand),
                        const SizedBox(width: 4),
                        Text('Pinned', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.brand)),
                      ],
                    ),
                  ),
                Text(note.body, style: const TextStyle(height: 1.4)),
                const SizedBox(height: 8),
                Text(
                  '${note.authorEmail} · ${Fmt.ago(note.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.textMuted),
                ),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete note',
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: p.textMuted),
            ),
        ],
      ),
    );
  }
}

class NoteDraft {
  const NoteDraft(this.body, this.pinned);
  final String body;
  final bool pinned;
}

/// Note text + "pin to the top" switch (promptText has no room for the switch).
class NoteSheet extends StatefulWidget {
  const NoteSheet({super.key});

  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  final _c = TextEditingController();
  bool _pinned = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final body = _c.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add note', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Visible to everyone on the Counterbase team. Never shown to the company.',
                style: TextStyle(color: p.textMuted, height: 1.4)),
            const SizedBox(height: 16),
            TextField(
              controller: _c,
              autofocus: true,
              maxLines: 6,
              minLines: 3,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              title: const Text('Pin to the top'),
              subtitle: Text('Pinned notes are listed first.', style: TextStyle(color: p.textMuted)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: body.isEmpty ? null : () => Navigator.pop(context, NoteDraft(body, _pinned)),
              child: const Text('Save note'),
            ),
          ],
        ),
      ),
    );
  }
}
