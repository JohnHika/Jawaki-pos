/// A customer's full account on this device: every completed purchase and
/// every debt payment, oldest first, with the totals a shop owner is asked
/// about. Pure, so the PDF and the spreadsheet show the same figures.
class LocalStatement {
  LocalStatement({
    required this.customerName,
    required this.customerPhone,
    required this.balance,
    required List<Map<String, dynamic>> sales,
    required List<Map<String, dynamic>> payments,
  })  : purchases = [...sales]..sort(_byDate('createdAt')),
        payments = [...payments]..sort(_byDate('collectedAt'));

  final String customerName;
  final String? customerPhone;

  /// What the customer owes now.
  final double balance;
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> payments;

  double get totalBought => _sum(purchases, 'total');

  /// Bought on credit, in full (split payments are not broken down here).
  double get boughtOnCredit => _sum(
      purchases.where((sale) =>
          sale['paymentMethod']?.toString().toUpperCase() == 'CREDIT'),
      'total');
  double get totalPaidOnAccount => _sum(payments, 'amount');

  static double _sum(Iterable<Map<String, dynamic>> rows, String key) {
    var cents = 0;
    for (final row in rows) {
      cents += (((row[key] as num?)?.toDouble() ?? 0) * 100).round();
    }
    return cents / 100;
  }

  static int Function(Map<String, dynamic>, Map<String, dynamic>) _byDate(
          String key) =>
      (a, b) => (a[key]?.toString() ?? '').compareTo(b[key]?.toString() ?? '');
}

String statementMethodLabel(String? method) =>
    switch (method?.trim().toUpperCase()) {
      'CASH' => 'Cash',
      'MPESA' => 'M-Pesa',
      'MPESA_RECORDED' => 'M-Pesa (recorded)',
      'BANK' => 'Bank',
      'BANK_RECORDED' => 'Bank transfer (recorded)',
      'CREDIT' => 'On credit',
      'SPLIT' => 'Split',
      'CARD' => 'Card',
      null || '' => 'Not recorded',
      final other => other,
    };

/// "08/11/2026 14:05" from a stored date, in the phone's time.
String statementDateTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}
