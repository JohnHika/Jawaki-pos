import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/injection.dart';
import '../../../core/providers/tenant_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/storage_service.dart';
import '../../sales/domain/recorded_payment.dart';
import '../../sales/presentation/providers/sales_provider.dart'
    show localReceiptContact;
import '../domain/setup_checklist.dart';

/// The shop's setup checklist, read from the phone. Steps the app can see
/// done are noted in the database the first time, so the shop keeps a record
/// of when it was set up.
final setupChecklistProvider =
    FutureProvider.autoDispose<SetupChecklist>((ref) async {
  final logoUrl = ref.watch(tenantIdentityProvider).logoUrl;
  final auth = getIt<AuthService>();
  final db = getIt<AppDatabase>();
  final storage = getIt<StorageService>();
  final contact =
      await localReceiptContact(db, auth.currentUser, auth.branchId ?? '');
  final facts = SetupFacts(
    hasReceiptDetails:
        contact.address.trim().isNotEmpty && contact.phone.trim().isNotEmpty,
    productCount: await db.getProductCount(),
    staffCount: storage.getLocalStaffAccounts().length,
    hasPaymentTill: _tillNumber(storage).isNotEmpty,
    hasLogo: logoUrl?.trim().isNotEmpty == true,
    saleCount: await db.getLocalCompletedSaleCount(),
    notes: await db.getSetupNotes(),
  );
  final checklist = SetupChecklist.from(facts);
  final by = auth.currentUser?['name']?.toString();
  for (final key in checklist.doneKeys) {
    if (facts.notes[key] != 'DONE') {
      await db.noteSetupStep(key, notedBy: by);
    }
  }
  return checklist;
});

String _tillNumber(StorageService storage) {
  final json = storage.getRecordedPaymentRulesJson();
  if (json == null || json.isEmpty) return '';
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map<String, dynamic>) {
      return RecordedPaymentRules.fromJson(decoded).tillNumber;
    }
  } catch (_) {
    // A damaged setting reads as not set up yet.
  }
  return '';
}
