/// Whether a receipt matches what the cashier typed in the search box.
///
/// Matches the short code printed on the card (`#ABCD1234`), the full receipt
/// number, customer name, payment method, and customer phone. Phones compare
/// by digits only, so `0712 345 678` finds `+254712345678` and vice versa.
bool receiptMatchesQuery({
  required String saleId,
  required String receiptNumber,
  required String paymentMethod,
  required String query,
  String? customerName,
  String? customerPhone,
}) {
  final needle = query.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
  if (needle.isEmpty) return true;

  final shortCode = saleId.length >= 8 ? saleId.substring(0, 8) : saleId;
  final textFields = <String>[
    shortCode,
    receiptNumber,
    paymentMethod,
    customerName ?? '',
  ];
  if (textFields.any((field) => field.toLowerCase().contains(needle))) {
    return true;
  }

  final needleDigits = needle.replaceAll(RegExp(r'\D'), '');
  // A couple of digits would match nearly every phone; require a real fragment.
  if (needleDigits.length < 3) return false;
  final phone = customerPhone ?? '';
  final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
  return phoneDigits.contains(needleDigits) ||
      _localDigits(phone).contains(_localDigits(needleDigits));
}

/// Digits with a leading Kenyan country code or trunk zero removed, so
/// `+254712…`, `254712…` and `0712…` all reduce to `712…`.
String _localDigits(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('254') && digits.length > 9) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits;
}
