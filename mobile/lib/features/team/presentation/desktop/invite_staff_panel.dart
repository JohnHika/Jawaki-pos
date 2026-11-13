import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/desktop/adaptive_overlays.dart';
import '../../../../core/desktop/desktop_layout.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../settings/presentation/desktop/settings_desktop_widgets.dart'
    show desktopOutlinedStyle;
import '../screens/invite_staff_screen.dart' show defaultInviteRoleId;

/// Opens the invite form as a panel on the right edge of the page. Resolves to
/// true when an invitation was sent.
Future<bool?> showInviteStaffPanel(BuildContext context) =>
    showAdaptiveSheet<bool>(
      context: context,
      desktopStyle: DesktopSheetStyle.sidePanel,
      desktopWidth: 440,
      builder: (_) => const InviteStaffPanel(),
    );

/// The "Invite user" form for a computer: name, email, role and branch, a
/// short helper line and one button. It loads and sends exactly what the phone
/// form does (same roles, branches and invitation calls).
class InviteStaffPanel extends StatefulWidget {
  const InviteStaffPanel({super.key});

  @override
  State<InviteStaffPanel> createState() => _InviteStaffPanelState();
}

class _InviteStaffPanelState extends State<InviteStaffPanel> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _branches = [];
  String? _roleId;
  String? _branchId;
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final api = getIt<ApiClient>();
      final data =
          await Future.wait([api.getStaffInvitationRoles(), api.getBranches()]);
      if (!mounted) return;
      final roles =
          data[0].whereType<Map>().map(Map<String, dynamic>.from).toList();
      final branches =
          data[1].whereType<Map>().map(Map<String, dynamic>.from).toList();
      setState(() {
        _roles = roles;
        _branches = branches;
        _roleId = defaultInviteRoleId(roles);
        _branchId =
            branches.isNotEmpty ? branches.first['id'].toString() : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await getIt<ApiClient>().createStaffInvitation(
        email: _email.text.trim(),
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        roleId: _roleId!,
        branchId: _branchId!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendError = 'We could not send the invitation. Check the details '
              'and try again.';
        });
      }
    }
  }

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;

  String? _emailCheck(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v.trim())
        ? null
        : 'Enter a valid email address';
  }

  @override
  Widget build(BuildContext context) {
    final p = DesktopPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Invite user',
                  style: GoogleFonts.sora(
                    color: p.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(child: _body(context, p)),
      ],
    );
  }

  Widget _body(BuildContext context, DesktopPalette p) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load roles and branches',
                style: GoogleFonts.plusJakartaSans(
                  color: p.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Check your internet connection and try again.',
                style: GoogleFonts.plusJakartaSans(color: p.textMuted),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                style: desktopOutlinedStyle(context),
                onPressed: _load,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_roles.isEmpty || _branches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Add at least one role and one active branch before inviting '
            'people.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: p.textMuted),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Their email gets a time-limited code to accept the '
                    'invitation.',
                    style: GoogleFonts.plusJakartaSans(
                      color: p.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('invite-first-name'),
                          controller: _first,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          validator: _required,
                          decoration:
                              const InputDecoration(labelText: 'First name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('invite-last-name'),
                          controller: _last,
                          textInputAction: TextInputAction.next,
                          validator: _required,
                          decoration:
                              const InputDecoration(labelText: 'Last name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const ValueKey('invite-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailCheck,
                    onFieldSubmitted: (_) => _send(),
                    decoration:
                        const InputDecoration(labelText: 'Email address'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('invite-role'),
                    initialValue: _roleId,
                    onChanged: (v) => setState(() => _roleId = v),
                    validator: (v) => v == null ? 'Choose a role' : null,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final r in _roles)
                        DropdownMenuItem(
                          value: r['id'].toString(),
                          child: Text(r['name']?.toString() ?? 'Unnamed'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('invite-branch'),
                    initialValue: _branchId,
                    onChanged: (v) => setState(() => _branchId = v),
                    validator: (v) => v == null ? 'Choose a branch' : null,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      for (final b in _branches)
                        DropdownMenuItem(
                          value: b['id'].toString(),
                          child: Text(b['name']?.toString() ?? 'Unnamed'),
                        ),
                    ],
                  ),
                  if (_sendError != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _sendError!,
                      style: GoogleFonts.plusJakartaSans(
                        color: p.dark
                            ? const Color(0xFFF97066)
                            : const Color(0xFFB42318),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('invite-send'),
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Sending…' : 'Send invitation'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
