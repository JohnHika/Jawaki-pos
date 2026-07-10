import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../../core/theme/design_system.dart';
import 'ai_chat_prefs.dart';

/// The "Add to chat" sheet (Camera / Photos / Files, Web search, Tool
/// access) shown when the user taps the "+" in the AI chat input, mirroring
/// the reference design. Camera/Photos capture an image and extract its
/// text on-device (OCR), handing that text back to the chat so it becomes
/// part of the next question — a real, offline-capable win even before
/// full gateway vision lands. [onAttachmentText] receives (label, text).
Future<void> showAddToChatSheet(
  BuildContext context, {
  required void Function(String label, String extractedText) onAttachmentText,
}) {
  return GlassBottomSheet.show<void>(
    context,
    title: 'Add to chat',
    initialSize: 0.55,
    maxSize: 0.7,
    child: _AddToChatBody(onAttachmentText: onAttachmentText),
  );
}

class _AddToChatBody extends StatefulWidget {
  final void Function(String label, String extractedText) onAttachmentText;
  const _AddToChatBody({required this.onAttachmentText});

  @override
  State<_AddToChatBody> createState() => _AddToChatBodyState();
}

class _AddToChatBodyState extends State<_AddToChatBody> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _capture(ImageSource source, String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      // On-device text recognition — extract any text from the photo so the
      // AI can read receipts, invoices, labels, shelf tags, etc. This works
      // offline and needs no gateway vision entitlement.
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      String extracted = '';
      try {
        final input = InputImage.fromFilePath(picked.path);
        final result = await recognizer.processImage(input);
        extracted = result.text.trim();
      } finally {
        await recognizer.close();
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      if (extracted.isEmpty) {
        showGlassSnackBar(
          context,
          'No readable text found in that image.',
          icon: Icons.image_not_supported_outlined,
          color: DesignColors.warning,
        );
        return;
      }
      widget.onAttachmentText('$label attachment', extracted);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showGlassSnackBar(
          context,
          'Could not read that image.',
          icon: Icons.error_outline_rounded,
          color: DesignColors.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefs = AiChatPrefs.instance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          // Row of attach tiles.
          Row(
            children: [
              Expanded(
                child: _AttachTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: () => _capture(ImageSource.camera, 'Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AttachTile(
                  icon: Icons.image_rounded,
                  label: 'Photos',
                  onTap: () => _capture(ImageSource.gallery, 'Photo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AttachTile(
                  icon: Icons.upload_file_rounded,
                  label: 'Files',
                  // Files reuses the gallery picker for images/documents for
                  // now (on-device OCR extracts text); a dedicated file
                  // picker can widen this to PDFs later.
                  onTap: () => _capture(ImageSource.gallery, 'File'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Web search toggle.
          _ToggleRow(
            icon: Icons.travel_explore_rounded,
            label: 'Web search',
            value: prefs.webSearch,
            onChanged: (v) => setState(() => prefs.webSearch = v),
          ),
          const SizedBox(height: 8),
          // Tool access toggle.
          _ToggleRow(
            icon: Icons.build_rounded,
            label: 'Tool access',
            subtitle: prefs.toolAccess ? 'Auto' : 'Off',
            value: prefs.toolAccess,
            onChanged: (v) => setState(() => prefs.toolAccess = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Camera, Photos and Files read text from an image on your device '
            'and add it to your next message.',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? DesignColors.darkTextTertiary
                  : DesignColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isDark
              ? DesignColors.darkSurfaceElevated
              : DesignColors.surfaceMuted,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 26,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? DesignColors.darkTextPrimary
                    : DesignColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? DesignColors.darkSurfaceElevated
            : DesignColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: isDark
                  ? DesignColors.darkTextSecondary
                  : DesignColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? DesignColors.darkTextPrimary
                        : DesignColors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? DesignColors.darkTextTertiary
                          : DesignColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: DesignColors.accent,
          ),
        ],
      ),
    );
  }
}
