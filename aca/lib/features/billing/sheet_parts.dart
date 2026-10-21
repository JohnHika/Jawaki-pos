import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';

/// Copies [text] and confirms with a toast.
Future<void> copyToClipboard(BuildContext context, String text, {String what = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, what);
}

/// Opens a standard modal bottom sheet for detail views: scrollable, safe-area
/// aware and never taller than 90 % of the screen.
Future<T?> showDetailSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
    builder: builder,
  );
}

/// Bottom-sheet confirmation like the shared `confirmAction`, but scrollable
/// and allowed to grow with its content, so long explanations never overflow
/// on small screens or with a large system font.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final p = context.aca;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.viewPaddingOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: p.textMuted, height: 1.45)),
          const SizedBox(height: 24),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ],
      ),
    ),
  );
  return ok ?? false;
}

/// Padding + scroll wrapper used inside [showDetailSheet].
class DetailSheetBody extends StatelessWidget {
  const DetailSheetBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Small upper-case heading that groups rows inside a detail sheet.
class SheetSectionTitle extends StatelessWidget {
  const SheetSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted),
      ),
    );
  }
}

/// Label on the left, value on the right; values wrap, and when [copyText] is
/// set a copy button sits at the end of the row.
class DetailRow extends StatelessWidget {
  const DetailRow(
    this.label,
    this.value, {
    super.key,
    this.valueWidget,
    this.copyText,
    this.copyLabel,
    this.mono = false,
    this.muted = false,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;

  /// When set, a copy icon copies this text.
  final String? copyText;
  final String? copyLabel;
  final bool mono;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final v = valueWidget ??
        Text(
          (value == null || value!.isEmpty) ? '—' : value!,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: muted ? p.textMuted : p.text,
            fontSize: mono ? 13 : null,
            fontFamily: mono ? 'monospace' : null,
          ),
        );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(label, style: TextStyle(color: p.textMuted)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: v),
          ),
          if (copyText != null)
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.copy_rounded, size: 18, color: p.textMuted),
              onPressed: () => copyToClipboard(context, copyText!, what: copyLabel ?? 'Copied'),
            ),
        ],
      ),
    );
  }
}

/// Hairline between detail rows.
class DetailDivider extends StatelessWidget {
  const DetailDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, color: context.aca.border);
}

/// Icon + single line of muted text, used for compact meta lines on cards.
class MetaLine extends StatelessWidget {
  const MetaLine(this.icon, this.text, {super.key, this.maxLines = 1});

  final IconData icon;
  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 14, color: p.textFaint),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: p.textMuted, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// Calm explanatory banner (icon + text) for help copy.
class HelpBanner extends StatelessWidget {
  const HelpBanner(this.text, {super.key, this.icon = Icons.info_outline_rounded, this.tone = Tone.info});

  final String text;
  final IconData icon;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: p.toneColor(tone)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: p.text, height: 1.4, fontSize: 13.5))),
        ],
      ),
    );
  }
}
