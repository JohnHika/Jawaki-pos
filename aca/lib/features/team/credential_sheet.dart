import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../account/sheet_kit.dart';

/// Which flow produced the one-time password; only the wording differs.
enum CredentialKind { created, reset }

/// Shows a staff member's sign-in email and their ONE-TIME temporary password.
///
/// The sheet cannot be swiped away, tapped away or closed with the back button:
/// the password is never shown again, so the only way out is "Done".
Future<void> showCredentialSheet(
  BuildContext context, {
  required TempCredential credential,
  required CredentialKind kind,
  required String name,
}) {
  return showFormSheet<void>(
    context,
    dismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _CredentialSheet(credential: credential, kind: kind, name: name),
    ),
  );
}

class _CredentialSheet extends StatelessWidget {
  const _CredentialSheet({required this.credential, required this.kind, required this.name});

  final TempCredential credential;
  final CredentialKind kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final created = kind == CredentialKind.created;
    return SheetBody(
      title: created ? 'Staff member added' : 'Password reset',
      message: created
          ? 'Give $name these sign-in details privately.'
          : '$name has a new temporary password. Give it to them privately.',
      children: [
        Text('EMAIL', style: TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.textMuted)),
        const SizedBox(height: 4),
        SelectableText(credential.email, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text('TEMPORARY PASSWORD',
            style: TextStyle(fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.textMuted)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          decoration: BoxDecoration(
            color: p.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.brand.withValues(alpha: 0.55)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              credential.temporaryPassword,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: p.text,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        CopyButton(text: credential.temporaryPassword, label: 'Copy password', copiedLabel: 'Password copied'),
        const SizedBox(height: 16),
        NoticeBox(
          created
              ? 'This password is shown only once. Copy it now. $name must choose their own password '
                  'the first time they sign in; until then they show as "Invite pending".'
              : 'This password is shown only once. Copy it now. $name is signed out everywhere and the '
                  'account is unlocked. They must choose their own password at their next sign-in.',
          title: 'Will not be shown again',
          icon: Icons.warning_amber_rounded,
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
