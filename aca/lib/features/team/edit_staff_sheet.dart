import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../account/sheet_kit.dart';
import 'team_logic.dart';

/// Edit a staff member's name and phone. Resolves to true when something was saved.
Future<bool?> showEditStaffSheet(BuildContext context, {required StaffMember staff}) =>
    showFormSheet<bool>(context, builder: (_) => _EditStaffSheet(staff: staff));

class _EditStaffSheet extends StatefulWidget {
  const _EditStaffSheet({required this.staff});
  final StaffMember staff;

  @override
  State<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends State<_EditStaffSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.staff.name);
  late final _phone = TextEditingController(text: widget.staff.phone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final nameChanged = name != widget.staff.name;
    final phoneChanged = phone != (widget.staff.phone ?? '').trim();
    if (!nameChanged && !phoneChanged) {
      Navigator.pop(context, false);
      return;
    }
    FocusScope.of(context).unfocus();
    final repo = context.read<AcaRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.updateStaff(
        widget.staff.id,
        name: nameChanged ? name : null,
        phone: phoneChanged ? phone : null,
      );
      if (mounted) Navigator.pop(context, true);
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
    return PopScope(
      canPop: !_busy,
      child: SheetBody(
        title: 'Edit details',
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
                  decoration: const InputDecoration(labelText: 'Full name', counterText: ''),
                  validator: validateStaffName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  enabled: !_busy,
                  maxLength: 30,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Phone', counterText: ''),
                  validator: validateStaffPhone,
                ),
                const SizedBox(height: 18),
                SubmitButton(label: 'Save', busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
