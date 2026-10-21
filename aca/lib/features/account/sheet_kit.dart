import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';

/// Small building blocks shared by the Account and Team sheets.
///
/// Why this exists: a snackbar raised while a bottom sheet is open renders
/// *behind* the sheet, so forms inside sheets must show their errors inline and
/// give copy feedback in the button itself.

/// Message to show a person for any failure.
String errorMessage(Object e) => e is ApiException ? e.message : 'Something went wrong. Try again.';

/// A keyboard-safe, scrollable bottom sheet. Pass [dismissible] false for sheets
/// that must not be closed by a stray tap (one-time credentials, backup codes).
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: builder,
  );
}

/// Confirmation sheet with the same look as the shared `confirmAction`, but
/// scrollable and allowed to use the full screen height. The shared one is capped
/// at 9/16 of the screen and overflows with long explanations at 1.3x text size.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showFormSheet<bool>(
    context,
    builder: (ctx) => SheetBody(
      title: title,
      message: message,
      children: [
        SubmitButton(label: confirmLabel, destructive: destructive, onPressed: () => Navigator.pop(ctx, true)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      ],
    ),
  );
  return ok ?? false;
}

/// Title, optional explanation and [children] laid out for a bottom sheet:
/// 24dp gutters, scrolls when the keyboard or a large font eats the space.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.title, this.message, required this.children});

  final String title;
  final String? message;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: TextStyle(color: p.textMuted, height: 1.4)),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Tinted callout: warnings, errors and "what happens next" notes.
class NoticeBox extends StatelessWidget {
  const NoticeBox(this.message, {super.key, this.tone = Tone.warning, this.icon, this.title});

  final String message;
  final String? title;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final color = p.toneColor(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon ?? Icons.info_outline_rounded, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                  ),
                Text(message, style: TextStyle(color: p.text, height: 1.4, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Server/validation error shown inside a form.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) =>
      NoticeBox(message, tone: Tone.danger, icon: Icons.error_outline_rounded);
}

/// Primary button of a form: shows a spinner while [busy] and ignores taps.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return FilledButton(
      style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white) : null,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
          : Text(label),
    );
  }
}

/// Copies [text] and flips to "Copied" for a couple of seconds, so the feedback
/// is visible even on top of a bottom sheet.
class CopyButton extends StatefulWidget {
  const CopyButton({super.key, required this.text, this.label = 'Copy', this.copiedLabel = 'Copied'});

  final String text;
  final String label;
  final String copiedLabel;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return OutlinedButton.icon(
      onPressed: _copy,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: _copied ? p.success : p.text,
        side: BorderSide(color: _copied ? p.success : p.border),
      ),
      icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
      label: Text(_copied ? widget.copiedLabel : widget.label),
    );
  }
}
