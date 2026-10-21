import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/repository.dart';
import 'license_logic.dart';
import 'tenants_logic.dart';

/// What the editor hands back after a successful save. [license] is the licence
/// the server returned (null if it returned nothing usable, so the caller re-reads it).
class LicenseEditResult {
  const LicenseEditResult(this.license);
  final LicenseView? license;
}

/// Full-screen licence editor. Sends only the fields that changed and pops with
/// a [LicenseEditResult] after saving (null when the user backs out).
class LicenseEditorScreen extends StatefulWidget {
  const LicenseEditorScreen({super.key, required this.tenantId, required this.tenantName, required this.license});

  final String tenantId;
  final String tenantName;
  final LicenseView license;

  @override
  State<LicenseEditorScreen> createState() => _LicenseEditorScreenState();
}

class _LicenseEditorScreenState extends State<LicenseEditorScreen> {
  late LicenseDraft _draft = LicenseDraft.from(widget.license);
  late final _branches = TextEditingController(text: widget.license.editableMaxBranches?.toString() ?? '');
  late final _users = TextEditingController(text: widget.license.editableMaxUsers?.toString() ?? '');
  late final _note = TextEditingController(text: widget.license.note ?? '');
  bool _saving = false;

  LicenseView get _orig => widget.license;

  LimitInput get _branchInput => parseLimit(_branches.text);
  LimitInput get _userInput => parseLimit(_users.text);
  bool get _noteTooLong => _note.text.trim().length > kLicenseNoteMax;
  bool get _valid => _branchInput.valid && _userInput.valid && !_noteTooLong;

  /// The draft with whatever is currently typed in the text fields.
  LicenseDraft get _current => LicenseDraft(
        enforcement: _draft.enforcement,
        choices: _draft.choices,
        validUntil: _draft.validUntil,
        maxBranches: _branchInput.value,
        maxUsers: _userInput.value,
        note: _note.text,
        reissueKey: _draft.reissueKey,
      );

  Map<String, dynamic> get _patch => buildLicensePatch(_orig, _current);
  bool get _dirty => _patch.isNotEmpty;

  @override
  void dispose() {
    _branches.dispose();
    _users.dispose();
    _note.dispose();
    super.dispose();
  }

  void _update(LicenseDraft d) => setState(() => _draft = d);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _draft.validUntil?.toLocal();
    final initial = current == null ? today.add(const Duration(days: 30)) : DateTime(current.year, current.month, current.day);
    final first = initial.isBefore(today) ? initial : today;
    final lastDefault = DateTime(now.year + 10, 12, 31);
    final last = initial.isAfter(lastDefault) ? initial : lastDefault;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Licence valid until',
    );
    if (picked == null || !mounted) return;
    final sameDay = current != null && DateUtils.isSameDay(current, picked);
    if (sameDay) return; // keep the exact stored time when the day did not change
    _update(_draft.copyWith(validUntil: DateTime(picked.year, picked.month, picked.day, 23, 59, 59)));
  }

  Future<void> _save() async {
    final patch = _patch;
    if (patch.isEmpty || !_valid || _saving) return;
    if (patch['enforcement'] == 'enforce') {
      final yes = await confirmAction(
        context,
        title: 'Turn on enforcement?',
        message: '${widget.tenantName} will be refused any module this licence does not include, '
            'and anything past its seat limits or its valid-until date. Check the module list first.',
        confirmLabel: 'Enforce licence',
        destructive: true,
      );
      if (!yes || !mounted) return;
    }
    final repo = context.read<AcaRepository>();
    final nav = Navigator.of(context);
    Map<String, dynamic>? result;
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () async {
        result = await repo.updateLicense(widget.tenantId, patch);
      },
      success: 'Licence updated',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      final r = result;
      nav.pop(LicenseEditResult(r == null || r.isEmpty ? null : LicenseView.fromJson(r)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final patch = _patch;
    final changes = licenseChangeCount(patch);

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await confirmAction(
          context,
          title: 'Discard your changes?',
          message: 'You have edits to this licence that are not saved.',
          confirmLabel: 'Discard changes',
          destructive: true,
        );
        if (discard) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit licence'),
              Text(widget.tenantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (_orig.unknownPlan)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _Banner(
                        tone: Tone.info,
                        icon: Icons.info_outline_rounded,
                        text: 'This company\'s plan is not on the price list, so every module stays open until you move it '
                            'to a real plan or set the modules below by hand.',
                      ),
                    ),
                  _enforcementCard(context),
                  const SectionHeader('Modules'),
                  _modulesCard(context),
                  const SectionHeader('Valid until'),
                  _validityCard(context),
                  const SectionHeader('Seat limits'),
                  _limitsCard(context),
                  const SectionHeader('Note and key'),
                  _noteCard(context),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.border))),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: FilledButton(
                    onPressed: (_dirty && _valid && !_saving) ? _save : null,
                    child: Text(!_dirty ? 'No changes yet' : 'Save ${plural(changes, 'change')}'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- sections

  Widget _enforcementCard(BuildContext context) {
    final p = context.aca;
    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enforcement', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: ButtonStyle(minimumSize: const WidgetStatePropertyAll(Size(0, 44)), visualDensity: VisualDensity.standard),
              segments: [
                for (final m in kEnforcementModes)
                  ButtonSegment<String>(value: m, label: FittedBox(fit: BoxFit.scaleDown, child: Text(enforcementLabel(m)))),
              ],
              selected: {_draft.enforcement},
              onSelectionChanged: (s) => _update(_draft.copyWith(enforcement: s.first)),
            ),
          ),
          const SizedBox(height: 10),
          Text(enforcementExplain(_draft.enforcement), style: TextStyle(color: p.textMuted, height: 1.4)),
          if (_draft.enforcement == 'enforce') ...[
            const SizedBox(height: 12),
            const _Banner(
              tone: Tone.warning,
              icon: Icons.warning_amber_rounded,
              text: 'Enforce will lock every module this licence does not include. People at this company will be '
                  'refused those features straight away, and also when they go over a seat limit or past the valid-until date.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _modulesCard(BuildContext context) {
    final p = context.aca;
    if (_orig.features.isEmpty) {
      return AcaCard(child: Text('The server did not list any modules for this licence.', style: TextStyle(color: p.textMuted)));
    }
    final keys = _orig.features.keys.toList();
    return AcaCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Column(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const Divider(height: 24),
            _moduleRow(context, keys[i]),
          ],
        ],
      ),
    );
  }

  Widget _moduleRow(BuildContext context, String key) {
    final p = context.aca;
    final f = _orig.features[key]!;
    final choice = _draft.choices[key] ?? f.choice;
    final changed = choice != f.choice;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(featureLabel(key), style: const TextStyle(fontWeight: FontWeight.w700))),
              if (changed) const StatusPill('Changed', tone: Tone.brand, dense: true),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            f.isOverride
                ? (f.allowed ? 'Now: granted by hand' : 'Now: revoked by hand')
                : (f.allowed ? 'Now: included in the plan' : 'Now: not in the plan'),
            style: TextStyle(color: p.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<FeatureChoice>(
              showSelectedIcon: false,
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, 44))),
              segments: const [
                ButtonSegment(value: FeatureChoice.planDefault, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Plan default'))),
                ButtonSegment(value: FeatureChoice.grant, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Grant'))),
                ButtonSegment(value: FeatureChoice.revoke, label: FittedBox(fit: BoxFit.scaleDown, child: Text('Revoke'))),
              ],
              selected: {choice},
              onSelectionChanged: (s) => _update(_draft.copyWith(choices: {..._draft.choices, key: s.first})),
            ),
          ),
        ],
      ),
    );
  }

  Widget _validityCard(BuildContext context) {
    final p = context.aca;
    final until = _draft.validUntil;
    final past = until != null && !until.isAfter(DateTime.now());
    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  until == null ? 'No expiry date' : Fmt.date(until),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: past ? p.danger : p.text),
                ),
              ),
              if (past) const StatusPill('In the past', tone: Tone.danger, dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'A licence with a date stops counting after it. With enforcement on, the modules are refused once it passes.',
            style: TextStyle(color: p.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 20),
                label: Text(until == null ? 'Pick a date' : 'Change date'),
              ),
              if (until != null)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _update(_draft.copyWith(clearValidUntil: true)),
                  child: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _limitsCard(BuildContext context) {
    final p = context.aca;
    String now(int? v) => v == null ? 'no limit' : '$v';
    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _branches,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Max branches',
              hintText: 'No limit',
              helperText: 'Now ${now(_orig.editableMaxBranches)}. Leave empty to follow the plan.',
              helperMaxLines: 2,
              errorText: _branchInput.valid ? null : 'Use a whole number of 1 or more',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _users,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Max users',
              hintText: 'No limit',
              helperText: 'Now ${now(_orig.editableMaxUsers)}. Leave empty to follow the plan.',
              helperMaxLines: 2,
              errorText: _userInput.valid ? null : 'Use a whole number of 1 or more',
            ),
          ),
          const SizedBox(height: 10),
          Text('Seat limits only block anyone when enforcement is on.', style: TextStyle(color: p.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _noteCard(BuildContext context) {
    final p = context.aca;
    final hasKey = _orig.licenseKey != null && _orig.licenseKey!.isNotEmpty;
    return AcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _note,
            maxLines: 4,
            minLines: 2,
            maxLength: kLicenseNoteMax,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Note (internal)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: hasKey && _draft.reissueKey,
            onChanged: hasKey ? (v) => _update(_draft.copyWith(reissueKey: v)) : null,
            title: const Text('Issue a new licence key'),
            subtitle: Text(
              hasKey
                  ? 'Replaces ${_orig.licenseKey} with a fresh key.'
                  : 'No key yet. One is issued automatically when you save.',
              style: TextStyle(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.tone, required this.icon, required this.text});

  final Tone tone;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    final c = p.toneColor(tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.toneFill(tone), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: p.text, height: 1.4, fontSize: 13.5))),
        ],
      ),
    );
  }
}
