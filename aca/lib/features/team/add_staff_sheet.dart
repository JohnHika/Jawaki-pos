import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../account/sheet_kit.dart';
import 'role_widgets.dart';
import 'team_logic.dart';

/// A staff member that was just created, with the one-time password to hand over.
class AddedStaff {
  const AddedStaff({required this.credential, required this.name});
  final TempCredential credential;
  final String name;
}

/// The "Add staff" form. On success the sheet closes and [onCreated] is called
/// with the one-time credential. It is a callback (not a return value) on purpose:
/// even if the sheet is dismissed while the request is in flight, the password
/// still reaches the caller and can be shown. It is never recoverable later.
Future<void> showAddStaffSheet(
  BuildContext context, {
  required List<RoleInfo> roles,
  required void Function(AddedStaff added) onCreated,
}) {
  return showFormSheet<void>(
    context,
    builder: (_) => _AddStaffSheet(roles: roles, onCreated: onCreated),
  );
}

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet({required this.roles, required this.onCreated});

  final List<RoleInfo> roles;
  final void Function(AddedStaff added) onCreated;

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  late final List<RoleInfo> _assignable = assignableRoles(widget.roles);
  late String? _role = defaultNewStaffRole(_assignable)?.role;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (_busy || role == null || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final repo = context.read<AcaRepository>();
    final onCreated = widget.onCreated;
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = await repo.createStaff(
        email: _email.text.trim(),
        name: name,
        role: role,
        phone: _phone.text.trim(),
      );
      if (mounted) Navigator.pop(context);
      onCreated(AddedStaff(credential: cred, name: name));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aca;
    return PopScope(
      canPop: !_busy,
      child: SheetBody(
        title: 'Add staff',
        message: 'They get a one-time temporary password and must choose their own when they first sign in.',
        children: [
          Form(
            key: _form,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[InlineError(_error!), const SizedBox(height: 14)],
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(labelText: 'Full name', counterText: ''),
                  validator: validateStaffName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  maxLength: 160,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Work email', counterText: ''),
                  validator: validateStaffEmail,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  enabled: !_busy,
                  maxLength: 30,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(labelText: 'Phone (optional)', counterText: ''),
                  validator: validateStaffPhone,
                ),
                const SizedBox(height: 20),
                Text('ROLE',
                    style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: p.textMuted)),
                const SizedBox(height: 8),
                for (final r in _assignable) ...[
                  RoleOptionTile(
                    role: r,
                    selected: r.role == _role,
                    onTap: _busy ? null : () => setState(() => _role = r.role),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                SubmitButton(label: 'Add staff', busy: _busy, onPressed: _role == null ? null : _submit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
