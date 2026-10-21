import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import 'account_logic.dart';
import 'sheet_kit.dart';

/// Shown once, right after two-step verification is turned on. The person cannot
/// leave until they confirm they saved the codes (the server never shows them again).
class BackupCodesScreen extends StatefulWidget {
  const BackupCodesScreen({super.key, required this.codes});

  final List<String> codes;

  @override
  State<BackupCodesScreen> createState() => _BackupCodesScreenState();
}

class _BackupCodesScreenState extends State<BackupCodesScreen> {
  bool _saved = false;

  /// Set when the person tries to leave early: the reminder appears next to the checkbox
  /// (a snackbar would float over it).
  bool _nudge = false;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final rows = <List<String>>[
      for (var i = 0; i < widget.codes.length; i += 2)
        widget.codes.sublist(i, i + 2 > widget.codes.length ? widget.codes.length : i + 2),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _nudge = true);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Backup codes'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: p.toneFill(Tone.success), shape: BoxShape.circle),
                          child: Icon(Icons.verified_user_rounded, color: p.success),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Two-step verification is on',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Save these backup codes now. If you lose your phone or cannot open your authenticator app, '
                      'a backup code lets you sign in. Each code works only once.',
                      style: TextStyle(color: p.textMuted, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    const NoticeBox(
                      'Store them somewhere safe, like a password manager or a printed page. '
                      'They will not be shown again.',
                      icon: Icons.warning_amber_rounded,
                    ),
                    const SizedBox(height: 16),
                    AcaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plural(widget.codes.length, 'backup code'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CopyButton(text: backupCodesText(widget.codes), label: 'Copy all', copiedLabel: 'Copied'),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (final row in rows)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  for (var i = 0; i < 2; i++) ...[
                                    if (i == 1) const SizedBox(width: 10),
                                    Expanded(child: i < row.length ? _CodeChip(row[i]) : const SizedBox.shrink()),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_nudge && !_saved)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(
                          'Save your backup codes first, then tick the box to continue.',
                          style: TextStyle(color: p.danger, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    CheckboxListTile(
                      value: _saved,
                      onChanged: (v) => setState(() => _saved = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('I have saved my backup codes somewhere safe'),
                    ),
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: _saved ? () => Navigator.pop(context, true) : null,
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: p.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          code,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: p.text,
          ),
        ),
      ),
    );
  }
}
