import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/desktop/adaptive_overlays.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/providers/business_layout_provider.dart';
import '../../../../core/theme/design_system.dart';
import '../widgets/sign_in_kit.dart';
import 'auth_desktop_kit.dart';

/// Picks the shop type in a dialog instead of a bottom sheet. Returns the
/// chosen profile id, or null when closed with Esc.
Future<String?> showShopTypeDialog(
  BuildContext context, {
  required String selectedId,
}) {
  return showAdaptiveSheet<String>(
    context: context,
    desktopWidth: 560,
    builder: (_) => _ShopTypePicker(selectedId: selectedId),
  );
}

class _ShopTypePicker extends StatefulWidget {
  const _ShopTypePicker({required this.selectedId});

  final String selectedId;

  @override
  State<_ShopTypePicker> createState() => _ShopTypePickerState();
}

class _ShopTypePickerState extends State<_ShopTypePicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BusinessLayoutPreset> get _matches {
    final query = _search.text.trim().toLowerCase();
    return businessLayoutPresets
        .where((profile) => businessLayoutProfileMatchesSearch(profile, query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    final profiles = _matches;
    return DesktopSheetFrame(
      title: 'Choose your shop type',
      subtitle:
          'This sets helpful starting defaults. You can fine-tune the layout later.',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (profiles.isNotEmpty) {
                Navigator.of(context).pop(profiles.first.id);
              }
            },
            decoration: InputDecoration(
              hintText: 'Search shop types',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (profiles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No shop types match.',
                  style: TextStyle(color: p.textMuted),
                ),
              ),
            )
          else
            for (final profile in profiles)
              ListTile(
                dense: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesktopTokens.controlRadius),
                ),
                selected: profile.id == widget.selectedId,
                selectedTileColor: p.selected,
                leading: Icon(profile.icon, color: p.textMuted, size: 22),
                title: Text(
                  profile.name,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  profile.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.textMuted, fontSize: 12.5),
                ),
                trailing: profile.id == widget.selectedId
                    ? Icon(Icons.check_rounded, color: p.text, size: 20)
                    : null,
                onTap: () => Navigator.of(context).pop(profile.id),
              ),
        ],
      ),
    );
  }
}

/// A person added to the team during set-up.
typedef SetupPersonDraft = ({String name, String role, String pin});

/// Adds a person to the team in a dialog. Returns null when cancelled.
Future<SetupPersonDraft?> showAddPersonDialog(
  BuildContext context, {
  required List<String> roles,
  required List<String> usedPins,
}) {
  return showAdaptiveSheet<SetupPersonDraft>(
    context: context,
    desktopWidth: 440,
    builder: (_) => _AddPersonForm(roles: roles, usedPins: usedPins),
  );
}

class _AddPersonForm extends StatefulWidget {
  const _AddPersonForm({required this.roles, required this.usedPins});

  final List<String> roles;
  final List<String> usedPins;

  @override
  State<_AddPersonForm> createState() => _AddPersonFormState();
}

class _AddPersonFormState extends State<_AddPersonForm> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  late String _role = widget.roles.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final pin = _pin.text.trim();
    String? problem;
    if (name.length < 2) {
      problem = 'Enter a name of at least 2 letters.';
    } else if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      problem = 'The PIN must be 4 to 6 digits.';
    } else if (widget.usedPins.contains(pin)) {
      problem = 'Someone you added already uses that PIN.';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((name: name, role: _role, pin: pin));
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return DesktopSheetFrame(
      title: 'Add a person',
      subtitle: 'They sign in with their own PIN, so every sale shows who made it.',
      actions: [
        AuthSecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AuthPrimaryButton(label: 'Add person', onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthField(
            label: 'Name',
            controller: _name,
            autofocus: true,
            autocorrect: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          Text(
            'Role',
            style: TextStyle(
              color: p.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final name in widget.roles)
                ChoiceChip(
                  label: Text(name),
                  selected: _role == name,
                  selectedColor: DesignColors.accent,
                  checkmarkColor: SignInPalette.onAccent,
                  labelStyle: TextStyle(
                    color: _role == name ? SignInPalette.onAccent : p.text,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _role = name),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AuthField(
            label: 'PIN, 4 to 6 digits',
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AuthNotice(message: _error!),
          ],
        ],
      ),
    );
  }
}

/// One thing to do after the shop is created.
class SetupNextItem {
  const SetupNextItem({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
}

/// "Your shop is ready" on a computer: the finished steps on the left, what
/// to do next on the right, Open my shop pinned below.
class SetupReadyDesktopView extends StatelessWidget {
  const SetupReadyDesktopView({
    super.key,
    required this.shopName,
    required this.stepLabels,
    required this.next,
    required this.onOpen,
    this.teamIssues = const [],
  });

  final String shopName;
  final List<String> stepLabels;
  final List<SetupNextItem> next;
  final VoidCallback onOpen;
  final List<String> teamIssues;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return AuthDesktopShell(
      formMaxWidth: AuthDesktop.wizardWidth,
      brand: AuthBrandPanel(
        statement: 'Your shop is set up on this computer.',
        steps: stepLabels,
        allStepsDone: true,
      ),
      actions: SizedBox(
        width: double.infinity,
        child: AuthPrimaryButton(
          label: 'Open my shop',
          autofocus: true,
          onPressed: onOpen,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              BusinessMark(name: shopName, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: AuthHeading(
                  title: 'Your shop is ready',
                  subtitle: '$shopName is set up on this computer.',
                ),
              ),
            ],
          ),
          if (teamIssues.isNotEmpty) ...[
            const SizedBox(height: 16),
            AuthNotice(
              warning: true,
              message:
                  'We could not add ${teamIssues.join(', ')}. Add them again in Settings, under Users.',
            ),
          ],
          const SizedBox(height: 22),
          Text(
            'Do these next',
            style: TextStyle(
              color: p.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: p.panelAlt,
              borderRadius: BorderRadius.circular(DesktopTokens.controlRadius + 2),
              border: Border.all(color: p.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < next.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  _NextRow(item: next[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Make a backup once you have sales. It protects you if the computer is lost.',
            style: TextStyle(color: p.textFaint, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({required this.item});

  final SetupNextItem item;

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return InkWell(
      onTap: item.onTap,
      mouseCursor: SystemMouseCursors.click,
      focusColor: p.selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: p.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.detail,
                    style: TextStyle(color: p.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textFaint),
          ],
        ),
      ),
    );
  }
}
