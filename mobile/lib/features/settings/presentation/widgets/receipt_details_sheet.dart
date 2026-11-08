import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/theme/design_system.dart';
import '../../../../core/widgets/form_kit.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/widgets/sign_in_kit.dart';
import '../../../sales/presentation/providers/sales_provider.dart'
    show localReceiptContact, receiptHeaderName;

typedef ReceiptDetails = ({String address, String phone});

/// Opens the receipt details sheet with what is saved now and keeps the
/// owner's changes in the shop's settings. True when something was saved.
Future<bool> editReceiptDetails(BuildContext context, WidgetRef ref) async {
  final auth = getIt<AuthService>();
  final tenant = auth.currentUser?['tenant'];
  final currentTenant =
      tenant is Map ? Map<String, dynamic>.from(tenant) : <String, dynamic>{};
  final rawSettings = currentTenant['settings'];
  final settings = rawSettings is Map
      ? Map<String, dynamic>.from(rawSettings)
      : <String, dynamic>{};
  final contact = await localReceiptContact(
    getIt<AppDatabase>(),
    auth.currentUser,
    auth.branchId ?? '',
  );
  if (!context.mounted) return false;
  final details = await showReceiptDetailsSheet(
    context,
    shopName: receiptHeaderName(auth.currentUser) ?? 'Your shop',
    address: contact.address,
    phone: contact.phone,
  );
  if (details == null || !context.mounted) return false;
  try {
    settings['receiptAddress'] = details.address;
    settings['receiptPhone'] = details.phone;
    await auth.updateTenantSession({...currentTenant, 'settings': settings});
    ref.read(authControllerProvider.notifier).refreshFromService();
    if (context.mounted) {
      showGlassSnackBar(
        context,
        'Receipt details saved',
        icon: Icons.check_circle_rounded,
        color: DesignColors.success,
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      showGlassSnackBar(
        context,
        'Could not save receipt details on this device. Please try again.',
        icon: Icons.error_outline_rounded,
        color: DesignColors.error,
      );
    }
    return false;
  }
}

/// Asks for the location and phone printed under the shop name on every
/// receipt. Returns null if closed without saving.
Future<ReceiptDetails?> showReceiptDetailsSheet(
  BuildContext context, {
  required String shopName,
  required String address,
  required String phone,
}) {
  return showModalBottomSheet<ReceiptDetails>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: SignInPalette.of(context).page,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReceiptDetailsSheet(
      shopName: shopName,
      address: address,
      phone: phone,
    ),
  );
}

class _ReceiptDetailsSheet extends StatefulWidget {
  const _ReceiptDetailsSheet({
    required this.shopName,
    required this.address,
    required this.phone,
  });

  final String shopName;
  final String address;
  final String phone;

  @override
  State<_ReceiptDetailsSheet> createState() => _ReceiptDetailsSheetState();
}

class _ReceiptDetailsSheetState extends State<_ReceiptDetailsSheet> {
  late final _address = TextEditingController(text: widget.address);
  late final _phone = TextEditingController(text: widget.phone);

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SignInPalette.of(context);
    final address = _address.text.trim();
    final phone = _phone.text.trim();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Receipt details',
                    style: DesignType.display.copyWith(
                      color: palette.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: palette.soft),
                ),
              ],
            ),
            Text(
              'Printed under your shop name, so customers know where to find you.',
              style: TextStyle(color: palette.soft, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _address,
              autofocus: widget.address.isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 64,
              onChanged: (_) => setState(() {}),
              decoration: kitFieldDecoration(context,
                  label: 'Location',
                  hint: 'For example, Mathais Plaza, Shop 4, Nairobi'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(16),
              ],
              onChanged: (_) => setState(() {}),
              decoration: kitFieldDecoration(context,
                  label: 'Shop phone', hint: 'For example, 0712 345 678'),
            ),
            const SizedBox(height: 16),
            // A small preview of the top of the receipt.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(DesignSpacing.radiusMd),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                children: [
                  Text(widget.shopName.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: DesignType.numeric(
                          fontSize: 13,
                          color: palette.ink,
                          fontWeight: FontWeight.w700)),
                  if (address.isNotEmpty)
                    Text(address,
                        textAlign: TextAlign.center,
                        style: DesignType.numeric(
                            fontSize: 12, color: palette.soft)),
                  if (phone.isNotEmpty)
                    Text('Tel: $phone',
                        textAlign: TextAlign.center,
                        style: DesignType.numeric(
                            fontSize: 12, color: palette.soft)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SignInButton(
              label: 'Save',
              onPressed: () => Navigator.of(context)
                  .pop<ReceiptDetails>((address: address, phone: phone)),
            ),
          ],
        ),
      ),
    );
  }
}
