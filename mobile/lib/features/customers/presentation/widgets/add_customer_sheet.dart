import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/form_kit.dart';

/// The local customer record created by the add sheet.
class AddedCustomer {
  const AddedCustomer({required this.id, required this.name});

  final String id;
  final String name;
}

/// Opens the "Add customer" sheet. Resolves to the saved customer, or null
/// if the sheet was dismissed without saving.
///
/// What a shop needs to track a credit client: a name, a phone number to
/// follow up on, where their shop is, and (only if relevant) the credit they
/// are taking today. Everything else stays out of the way.
Future<AddedCustomer?> showAddCustomerSheet(
  BuildContext context, {
  bool allowInitialCredit = true,
  String customerSingular = 'Customer',
}) {
  return GlassBottomSheet.show<AddedCustomer>(
    context,
    title: 'Add $customerSingular',
    initialSize: 0.9,
    maxSize: 0.95,
    child: AddCustomerForm(
      allowInitialCredit: allowInitialCredit,
      customerSingular: customerSingular,
    ),
  );
}

class AddCustomerForm extends StatefulWidget {
  const AddCustomerForm({
    super.key,
    this.allowInitialCredit = true,
    this.customerSingular = 'Customer',
  });

  final bool allowInitialCredit;
  final String customerSingular;

  @override
  State<AddCustomerForm> createState() => _AddCustomerFormState();
}

class _AddCustomerFormState extends State<AddCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _creditAmount = TextEditingController();

  bool _showNotes = false;
  bool _onCredit = false;
  DateTime? _dueDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _notes.dispose();
    _creditAmount.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The due-date shortcuts a shopkeeper actually uses.
  List<(String, DateTime)> get _dueShortcuts {
    final today = _today();
    final endOfMonth = DateTime(today.year, today.month + 1, 0);
    return [
      ('Tomorrow', today.add(const Duration(days: 1))),
      ('In 1 week', today.add(const Duration(days: 7))),
      ('In 2 weeks', today.add(const Duration(days: 14))),
      if (endOfMonth.difference(today).inDays > 2) ('End of month', endOfMonth),
    ];
  }

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _today().add(const Duration(days: 1)),
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = _onCredit
        ? (double.tryParse(_creditAmount.text.trim().replaceAll(',', '')) ?? 0)
        : 0.0;
    if (_onCredit && amount > 0 && _dueDate == null) {
      setState(() => _error = 'Pick when the first payment is due.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim();
    try {
      final db = getIt<AppDatabase>();
      final customerId = await db.insertOrGetCustomer(
        const Uuid().v4(),
        name,
        phone: _phone.text.trim(),
        location: _location.text.trim(),
        notes: _notes.text.trim(),
        initialBalance: amount,
      );
      // Queue the customer so the branch's other devices see them too.
      try {
        await getIt<SyncService>().queueSyncItem(
          tableName: 'customers',
          recordId: customerId,
          action: SyncAction.create,
          eventType: SyncEventType.customerCreated,
          data: {
            'id': customerId,
            'name': name,
            'phone': _phone.text.trim(),
            'address': _location.text.trim(),
            'notes': _notes.text.trim(),
          },
          deviceId: getIt<StorageService>().getDeviceId() ?? '',
          userId: getIt<AuthService>().userId ?? '',
        );
      } catch (_) {
        // Non-fatal: the customer is saved here and the periodic sync retries.
      }
      if (amount > 0 && _dueDate != null) {
        await db.addCustomerInstallment(
          customerId,
          amount,
          _dueDate!,
          note: 'Initial credit sale',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(AddedCustomer(id: customerId, name: name));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save this ${widget.customerSingular.toLowerCase()}. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title =
        isDark ? DesignColors.darkTextPrimary : DesignColors.textPrimary;
    final secondary =
        isDark ? DesignColors.darkTextSecondary : DesignColors.textSecondary;
    final panel =
        isDark ? DesignColors.darkSurfaceElevated : DesignColors.surfaceSubtle;
    final border =
        isDark ? DesignColors.darkBorder : DesignColors.surfaceBorder;
    final dateFormat = DateFormat('EEE d MMM');

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: kitFieldDecoration(
                      context,
                      label: '${widget.customerSingular} or shop name',
                      hint: 'e.g. Wanjiru Mini Mart',
                      prefixIcon: Icons.storefront_outlined,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    decoration: kitFieldDecoration(
                      context,
                      label: 'Phone number',
                      hint: '07xx xxx xxx',
                      prefixIcon: Icons.phone_outlined,
                      helper: 'Used to follow up on payments',
                    ),
                    validator: (v) {
                      final digits =
                          (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      if (digits.isEmpty) return 'Enter a phone number';
                      if (digits.length < 9) {
                        return 'That looks too short for a phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _location,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: _showNotes
                        ? TextInputAction.next
                        : TextInputAction.done,
                    decoration: kitFieldDecoration(
                      context,
                      label: 'Shop location (optional)',
                      hint: 'e.g. Gikomba, Stall 14',
                      prefixIcon: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_showNotes) ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _notes,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: kitFieldDecoration(
                        context,
                        label: 'Note (optional)',
                        hint: 'Anything worth remembering',
                        prefixIcon: Icons.notes_rounded,
                      ),
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showNotes = true),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add a note'),
                      ),
                    ),
                  const SizedBox(height: 14),
                  // Credit is a choice, not a form section: most new customers
                  // do not owe anything yet.
                  if (widget.allowInitialCredit)
                    Material(
                      color: panel,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        side: BorderSide(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            key: const ValueKey('credit-switch'),
                            value: _onCredit,
                            onChanged: (v) => setState(() {
                              _onCredit = v;
                              _error = null;
                            }),
                            activeThumbColor: Colors.white,
                            activeTrackColor: DesignColors.accent,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            secondary: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color:
                                    DesignColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    DesignSpacing.radiusSm),
                              ),
                              child: const Icon(Icons.credit_score_rounded,
                                  color: DesignColors.accent, size: 20),
                            ),
                            title: Text(
                              'Taking stock on credit',
                              style: TextStyle(
                                color: title,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              'Record what they owe and when it is due',
                              style:
                                  TextStyle(color: secondary, fontSize: 12.5),
                            ),
                          ),
                          if (_onCredit)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: _creditAmount,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.,]')),
                                    ],
                                    style: DesignType.numeric(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: title,
                                    ),
                                    decoration: kitFieldDecoration(
                                      context,
                                      label: 'Amount owed',
                                      hint: '0',
                                      prefixText: 'KES  ',
                                    ),
                                    validator: (v) {
                                      if (!_onCredit) return null;
                                      final amount = double.tryParse((v ?? '')
                                              .trim()
                                              .replaceAll(',', '')) ??
                                          0;
                                      if (amount <= 0) {
                                        return 'Enter the amount they owe';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  const FormLabel('First payment due'),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final (label, date) in _dueShortcuts)
                                        ChoicePill(
                                          label: label,
                                          selected: _sameDay(_dueDate, date),
                                          onTap: () => setState(() {
                                            _dueDate = date;
                                            _error = null;
                                          }),
                                        ),
                                      ChoicePill(
                                        label: 'Pick a date',
                                        icon: Icons.event_outlined,
                                        selected: _dueDate != null &&
                                            !_dueShortcuts.any((s) =>
                                                _sameDay(_dueDate, s.$2)),
                                        onTap: _pickDate,
                                      ),
                                    ],
                                  ),
                                  if (_dueDate != null) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Due ${dateFormat.format(_dueDate!)}',
                                      style: TextStyle(
                                        color: title,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DesignColors.error.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(DesignSpacing.radiusMd),
                        border: Border.all(
                            color: DesignColors.error.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: DesignColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        PinnedActionBar(
          child: GradientButton(
            label: 'Save ${widget.customerSingular}',
            icon: Icons.check_rounded,
            isLoading: _saving,
            height: 52,
            borderRadius: 14,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
