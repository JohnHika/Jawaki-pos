import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/adaptive_sheet.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/alive_feedback.dart';
import '../../../../core/widgets/motion_kit.dart';
import '../providers/layout_requests_provider.dart';
import 'layout_live_preview.dart';

String _ago(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

/// The shop's business type, with the live preview. A paid shop sees it as a
/// locked choice and asks for a change here; a shop still setting up picks
/// freely below this card.
class LayoutBusinessTypeCard extends StatelessWidget {
  const LayoutBusinessTypeCard({
    super.key,
    required this.layout,
    required this.locked,
    required this.requests,
    required this.canManage,
    required this.onRequestChange,
    required this.onApply,
    required this.onCancel,
    required this.onAddStore,
    this.wide = false,
  });

  final BusinessLayoutConfig layout;
  final bool locked;
  final List<LayoutChangeRequest> requests;
  final bool canManage;
  final VoidCallback onRequestChange;
  final ValueChanged<LayoutChangeRequest> onApply;
  final ValueChanged<LayoutChangeRequest> onCancel;
  final VoidCallback onAddStore;
  final bool wide;

  /// The newest request that matters right now.
  LayoutChangeRequest? get _latest => requests.isEmpty ? null : requests.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final preset = layout.preset;
    final accent = preset.accent ?? DesignColors.accent;
    final surface = isDark ? DesignColors.darkSurfaceElevated : Colors.white;
    final border = isDark ? DesignColors.darkBorder : DesignColors.surfaceBorderLight;
    final secondary = isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final latest = _latest;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(preset.icon, color: accent, size: 25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locked ? 'YOUR BUSINESS TYPE' : 'BUSINESS TYPE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          preset.description,
          style: theme.textTheme.bodySmall?.copyWith(color: secondary, height: 1.4),
        ),
        if (preset.highlights.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final h in preset.highlights)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    h,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
                  ),
                ),
            ],
          ),
        ],
        if (locked) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 15, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Locked to the business type you set up and paid for.',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            final sideBySide = c.maxWidth >= 330;
            if (!sideBySide) return header;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: header),
                const SizedBox(width: 14),
                LayoutLivePreview(layout: layout, wide: wide, height: wide ? 120 : 168),
              ],
            );
          }),
          if (locked) ...[
            const SizedBox(height: 14),
            _RequestArea(
              latest: latest,
              layout: layout,
              canManage: canManage,
              onRequestChange: onRequestChange,
              onApply: onApply,
              onCancel: onCancel,
              onAddStore: onAddStore,
            ),
          ],
        ],
      ),
    );
  }
}

class _RequestArea extends StatelessWidget {
  const _RequestArea({
    required this.latest,
    required this.layout,
    required this.canManage,
    required this.onRequestChange,
    required this.onApply,
    required this.onCancel,
    required this.onAddStore,
  });

  final LayoutChangeRequest? latest;
  final BusinessLayoutConfig layout;
  final bool canManage;
  final VoidCallback onRequestChange;
  final ValueChanged<LayoutChangeRequest> onApply;
  final ValueChanged<LayoutChangeRequest> onCancel;
  final VoidCallback onAddStore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = latest;

    // Approved and not applied yet: the owner chooses when to switch.
    final applied = request != null &&
        request.isApproved &&
        request.toProfileId == layout.profileId;
    if (request != null && request.isApproved && !applied) {
      final target = businessLayoutPreset(request.toProfileId);
      return _Banner(
        key: const ValueKey('approved'),
        color: DesignColors.success,
        icon: Icons.verified_rounded,
        title: 'Approved: ${target.name}',
        message: request.decisionNote?.isNotEmpty == true
            ? request.decisionNote!
            : 'Your change was approved. Apply it when you are ready.',
        action: canManage
            ? FilledButton.icon(
                onPressed: () => onApply(request),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text('Switch to ${target.name}'),
              )
            : null,
      );
    }

    if (request != null && request.isPending) {
      final target = businessLayoutPreset(request.toProfileId);
      return _Banner(
        key: const ValueKey('pending'),
        color: DesignColors.warning,
        icon: Icons.hourglass_top_rounded,
        title: 'Waiting for review: ${target.name}',
        message: 'Sent ${_ago(request.createdAt)}. We will tell you as soon as it is decided.',
        action: canManage
            ? TextButton(
                onPressed: () => onCancel(request),
                child: const Text('Withdraw request'),
              )
            : null,
      );
    }

    final declined = request != null && request.isRejected
        ? _Banner(
            key: const ValueKey('rejected'),
            color: DesignColors.error,
            icon: Icons.info_outline_rounded,
            title: 'Not approved: ${businessLayoutPreset(request.toProfileId).name}',
            message: request.decisionNote?.isNotEmpty == true
                ? request.decisionNote!
                : 'You can send a new request with more detail.',
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (declined != null) ...[declined, const SizedBox(height: 12)],
        if (canManage)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRequestChange,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Request a change'),
              ),
              OutlinedButton.icon(
                onPressed: onAddStore,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Add a store'),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Text(
          'Selling something different, like food next to a bookshop? Add another store. Each store keeps its own business type.',
          style: theme.textTheme.bodySmall?.copyWith(
            height: 1.4,
            color: theme.brightness == Brightness.dark
                ? DesignColors.darkTextSecondary
                : DesignColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopIn(
      beginScale: .96,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(message, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sheet for asking the Counterbase team to change the shop's business type.
/// Returns the sent request, or null if the owner backed out.
Future<LayoutChangeRequest?> showLayoutChangeRequestSheet(
  BuildContext context, {
  required String currentProfileId,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showAdaptiveModalSheet<LayoutChangeRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? DesignColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _RequestSheet(currentProfileId: currentProfileId),
  );
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({required this.currentProfileId});
  final String currentProfileId;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  final _reason = TextEditingController();
  String? _selected;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// A listed type if one is ticked; otherwise the custom layout, so a plain
  /// written request ("I need X") still goes through.
  String? get _target =>
      _selected ?? (widget.currentProfileId != 'custom' ? 'custom' : null);

  bool get _valid => _target != null && _reason.text.trim().length >= 10;

  Future<void> _send() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final request = await ref.read(layoutRequestsApiProvider).create(
            toProfileId: _target!,
            reason: _reason.text.trim(),
          );
      HapticService().success();
      if (mounted) Navigator.of(context).pop(request);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = LayoutRequestsApi.messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final options = businessLayoutPresets
        .where((p) => p.id != widget.currentProfileId)
        .toList(growable: false);
    final current = businessLayoutPreset(widget.currentProfileId);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? DesignColors.darkBorder : Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ask for a change',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'Your shop is set up as ${current.name}. Describe what you need. Pick a type below if one fits, or just write it; "Custom layout" is for anything else. We will review it and reply here.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: secondary, height: 1.4),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RadioGroup<String>(
                groupValue: _selected,
                onChanged: (v) {
                  if (!_sending) setState(() => _selected = v);
                },
                child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  for (final p in options)
                    RadioListTile<String>(
                      value: p.id,
                      enabled: !_sending,
                      activeColor: p.accent ?? DesignColors.accent,
                      secondary: CircleAvatar(
                        backgroundColor: (p.accent ?? DesignColors.accent).withValues(alpha: .14),
                        child: Icon(p.icon, color: p.accent ?? DesignColors.accent, size: 20),
                      ),
                      title: Text(p.name),
                      subtitle: Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _reason,
                    enabled: !_sending,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Why do you need this change?',
                      hintText: 'For example: we are replacing the bookshop with a food counter.',
                      border: OutlineInputBorder(),
                      helperText: 'At least 10 characters',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_error!, style: const TextStyle(color: DesignColors.error)),
                    ),
                ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _valid && !_sending ? _send : null,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send request'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Short confirmation after a request is sent.
void showLayoutRequestSent(BuildContext context) => Alive.done(
      context,
      'Request sent. We will reply here and notify you.',
      icon: Icons.send_rounded,
    );
