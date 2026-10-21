import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// Pure helpers for the Billing screens (no widgets, no network) so the rules
/// that decide what the finance team reads can be unit-tested.

/// Provider value the backend stores on a goodwill-credit invoice.
const String creditProvider = 'CREDIT';

/// Credits keep their reason in `reference`, prefixed with this marker.
const String creditReferencePrefix = 'CREDIT:';

/// Friendly name for an invoice `provider` value.
///
/// Known values come from the Counterbase billing code (Paystack card checkout,
/// Jenga M-Pesa STK push, manual M-Pesa reconciliation, goodwill credits);
/// anything unknown is prettified instead of shown raw.
String providerLabel(String? provider) {
  final p = provider?.trim().toUpperCase() ?? '';
  switch (p) {
    case '':
      return 'Not paid yet';
    case 'PAYSTACK':
      return 'Paystack';
    case 'PAYSTACK_INITIALIZING':
      return 'Paystack (checkout started)';
    case 'PAYSTACK_FAILED':
      return 'Paystack (failed)';
    case 'JENGA_STK':
      return 'M-Pesa STK push';
    case 'MPESA_MANUAL':
      return 'M-Pesa (manual)';
    case 'PESAPAL_CARD':
      return 'Card (Pesapal)';
    case creditProvider:
      return 'Goodwill credit';
  }
  return Fmt.label(p);
}

/// The reason behind a goodwill credit (`reference` is "CREDIT:" followed by the reason), or
/// null when [reference] is not a credit reference or carries no reason.
String? creditReason(String? reference) {
  final r = reference?.trim();
  if (r == null || !r.toUpperCase().startsWith(creditReferencePrefix)) return null;
  final reason = r.substring(creditReferencePrefix.length).trim();
  return reason.isEmpty ? null : reason;
}

/// What to show as "reference" for an invoice: credits show their reason,
/// everything else shows the reference as stored. Null when there is nothing.
String? invoiceReferenceText(Invoice invoice) {
  if (invoice.isCredit) return creditReason(invoice.reference);
  final r = invoice.reference?.trim();
  return (r == null || r.isEmpty) ? null : r;
}

String invoiceStatusLabel(String? status) {
  switch (status) {
    case 'PAID':
      return 'Paid';
    case 'PENDING':
      return 'Pending';
    case 'PENDING_CONFIRMATION':
      return 'Awaiting confirmation';
  }
  return Fmt.label(status);
}

Tone invoiceStatusTone(String? status) {
  switch (status) {
    case 'PAID':
      return Tone.success;
    case 'PENDING':
    case 'PENDING_CONFIRMATION':
      return Tone.warning;
  }
  return Tone.neutral;
}

/// Anything not yet PAID can be reconciled by hand (the server rejects PAID ones).
bool invoiceCanBeMarkedPaid(Invoice invoice) => invoice.status != 'PAID';

/// "42 invoices", "1 pending invoice", "0 paid invoices".
String invoiceCountLabel(int total, String? status) {
  final qualifier = switch (status) {
    'PENDING' => 'pending ',
    'PAID' => 'paid ',
    _ => '',
  };
  return '$total $qualifier${total == 1 ? 'invoice' : 'invoices'}';
}

/// "1 Oct – 31 Oct" (or with years when [withYear]); null when neither end is known.
String? periodLabel(DateTime? start, DateTime? end, {bool withYear = false}) {
  if (start == null && end == null) return null;
  String f(DateTime? d) => withYear ? Fmt.date(d) : Fmt.dateShort(d);
  return '${f(start)} – ${f(end)}';
}

/// "Paid 2 d ago" for settled invoices, otherwise "Created 3 d ago".
String invoiceTimelineLabel(Invoice invoice, {DateTime? now}) {
  if (invoice.isPaid && invoice.paidAt != null) {
    return 'Paid ${Fmt.ago(invoice.paidAt, now: now)}';
  }
  return 'Created ${Fmt.ago(invoice.createdAt, now: now)}';
}

// ------------------------------------------------------------- M-Pesa codes

final RegExp _mpesaCode = RegExp(r'^[A-Z0-9]{8,15}$');

/// Trimmed, upper-cased code; null when blank.
String? normalizeMpesaCode(String? raw) {
  final c = raw?.replaceAll(RegExp(r'\s+'), '').toUpperCase() ?? '';
  return c.isEmpty ? null : c;
}

/// Same shape the billing service accepts for a client-submitted code.
bool isValidMpesaCode(String code) => _mpesaCode.hasMatch(code);

/// Validation message for the optional code field; null when blank or valid.
String? mpesaCodeError(String? raw) {
  final c = normalizeMpesaCode(raw);
  if (c == null || isValidMpesaCode(c)) return null;
  return 'Use 8–15 letters and numbers, exactly as in the M-Pesa message';
}

// ------------------------------------------------------------------- claims

/// A claim is only actionable while its invoice is still unpaid.
bool claimNeedsAction(Claim claim) => claim.invoiceStatus != 'PAID';

int actionableClaimCount(Iterable<Claim> claims) => claims.where(claimNeedsAction).length;

/// Claims that still need reconciling first, otherwise the server's order
/// (newest first) is kept.
List<Claim> sortClaims(Iterable<Claim> claims) {
  final list = claims.toList();
  return [
    ...list.where(claimNeedsAction),
    ...list.where((c) => !claimNeedsAction(c)),
  ];
}
