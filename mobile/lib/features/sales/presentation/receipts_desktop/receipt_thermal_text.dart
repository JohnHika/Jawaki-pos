import '../../../../core/di/injection.dart';
import '../../../../core/services/auth_service.dart';
import '../../domain/recorded_payment.dart';

/// Character width of a 58mm thermal roll (esc_pos_utils PaperSize.mm58).
const int thermalColumns58mm = 32;

/// Character width of an 80mm thermal roll.
const int thermalColumns80mm = 48;

/// Whether receipts show tax, as set on the signed-in workspace.
bool receiptShowsTax() {
  try {
    return getIt<AuthService>().showTaxOnReceipt;
  } catch (_) {
    return false;
  }
}

/// Builds the monospace text block a receipt prints as, laid out to the same
/// column grid as the thermal printer, so the on-screen preview matches the
/// paper line for line. The phone receipt page and the desktop inspector both
/// draw this text.
///
/// [receipt] is the map `receiptProvider` produces. [fallbackNumber] is shown
/// when the sale has no receipt number yet.
String renderThermalReceiptText(
  Map<String, dynamic> receipt, {
  required String fallbackNumber,
  required bool showTax,
  int columns = thermalColumns58mm,
}) {
  final items = receipt['items'] as List? ?? [];
  final b = StringBuffer();
  final w = columns;

  String center(String s) {
    if (s.length >= w) return s.substring(0, w);
    final pad = (w - s.length) ~/ 2;
    return '${' ' * pad}$s';
  }

  // A left label and a right value on the same line, right-justified.
  String lr(String left, String right) {
    final maxLeft = w - right.length - 1;
    var l = left;
    if (l.length > maxLeft) l = l.substring(0, maxLeft);
    final gap = w - l.length - right.length;
    return '$l${' ' * (gap < 1 ? 1 : gap)}$right';
  }

  // Wrap a long product name across lines at the column width, indenting
  // continuation lines so it reads as one item.
  List<String> wrapName(String name, {int indent = 0}) {
    final avail = w - indent;
    if (name.length <= avail) return [' ' * indent + name];
    final out = <String>[];
    var rest = name;
    var first = true;
    while (rest.isNotEmpty) {
      final take = (first ? avail : w - 2);
      final pad = first ? indent : 2;
      if (rest.length <= take) {
        out.add(' ' * pad + rest);
        break;
      }
      // Break on the last space within the window if there is one.
      var cut = rest.substring(0, take);
      final sp = cut.lastIndexOf(' ');
      if (sp > take ~/ 2) cut = cut.substring(0, sp);
      out.add(' ' * pad + cut.trimRight());
      rest = rest.substring(cut.length).trimLeft();
      first = false;
    }
    return out;
  }

  String money(num v) => v.toStringAsFixed(2);
  final rule = '-' * w;
  final dblRule = '=' * w;

  // Header: store name + address, centred.
  b.writeln(center(
      (receipt['branchName'] ?? 'POS Store').toString().toUpperCase()));
  final addr = (receipt['branchAddress'] ?? '').toString();
  if (addr.isNotEmpty) {
    for (final l in wrapName(addr)) {
      b.writeln(center(l.trim()));
    }
  }
  final phone = (receipt['branchPhone'] ?? '').toString();
  if (phone.isNotEmpty) b.writeln(center('Tel: $phone'));
  b.writeln(rule);

  // VOIDED banner: impossible to miss.
  final isVoided =
      (receipt['status'] ?? '').toString().toUpperCase() == 'VOIDED';
  if (isVoided) {
    b.writeln(center('*** VOIDED SALE ***'));
    final vr = (receipt['voidReason'] ?? '').toString();
    if (vr.isNotEmpty) {
      for (final l in wrapName('Reason: $vr')) {
        b.writeln(l);
      }
    }
    b.writeln(rule);
  }

  // Receipt meta.
  final rcp = receipt['receiptNumber'] ?? fallbackNumber;
  b.writeln('Receipt #$rcp');
  b.writeln(_formatDateTime(receipt['createdAt']));
  if (receipt['cashierName'] != null) {
    b.writeln('Served by: ${receipt['cashierName']}');
  }
  if (receipt['customerName'] != null) {
    b.writeln('Customer: ${receipt['customerName']}');
  }
  if (receipt['customerPhone'] != null) {
    b.writeln('Phone: ${receipt['customerPhone']}');
  }
  b.writeln(rule);

  // Items. Each line: the product name (wrapped), then an indented detail
  // line showing how it was sold. When sold as a multi-unit tier (box/pack
  // with quantityPerUnit > 1), also show the per-base-unit price.
  for (final item in items) {
    final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
    final name = (item['productName'] ?? item['name'] ?? '').toString();
    final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
    final total = (item['total'] as num?)?.toDouble() ?? 0;
    final unit = (item['unit'] ?? '').toString().trim();
    final perUnit = (item['quantityPerUnit'] as num?)?.toDouble() ?? 0;

    for (final l in wrapName(name)) {
      b.writeln(l);
    }

    final unitLabel = unit.isNotEmpty ? ' $unit' : '';
    b.writeln(lr('  ${_formatQuantity(qty)}$unitLabel @ ${money(unitPrice)}',
        money(total)));

    if (unit.isNotEmpty && perUnit > 1) {
      final perPiece = unitPrice / perUnit;
      final pieces = perUnit * qty;
      b.writeln(
          '    (${_formatQuantity(pieces)} pcs @ ${money(perPiece)} each)');
    }
  }
  b.writeln(rule);

  // Totals.
  final subtotal = (receipt['subtotal'] as num?)?.toDouble() ?? 0;
  b.writeln(lr('Subtotal', money(subtotal)));
  final discount = (receipt['discount'] as num?)?.toDouble() ?? 0;
  if (discount > 0) {
    b.writeln(lr('Discount', '-${money(discount)}'));
  }
  final tax = (receipt['tax'] as num?)?.toDouble() ?? 0;
  if (showTax && tax > 0) {
    b.writeln(lr('Tax', money(tax)));
  }
  final grand = (receipt['total'] as num?)?.toDouble() ?? 0;
  b.writeln(dblRule);
  b.writeln(lr('TOTAL  KES', money(grand)));
  b.writeln(dblRule);

  // Payment detail: how it was paid, in full.
  final method = (receipt['paymentMethod'] ?? 'CASH').toString().toUpperCase();
  final tenders = receipt['paymentTenders'] as List?;
  if (method == 'SPLIT' && tenders != null && tenders.isNotEmpty) {
    b.writeln('Paid by (split):');
    for (final t in tenders) {
      final m = (t['method'] ?? '').toString();
      final amt = (t['amount'] as num?)?.toDouble() ?? 0;
      b.writeln(lr('  $m', money(amt)));
    }
  } else if (RecordedPaymentMethod.isRecorded(method)) {
    final recorded = RecordedPaymentDetails.tryParse(
        receipt['paymentReference']?.toString());
    b.writeln(lr('Paid by', RecordedPaymentMethod.label(method)));
    if (recorded != null) {
      b.writeln(lr('  Ref', recorded.code));
      if (recorded.recordedByName.isNotEmpty) {
        b.writeln(lr('  Recorded by', recorded.recordedByName));
      }
      if (recorded.approvedByName != null) {
        b.writeln(lr('  Approved by', recorded.approvedByName!));
      }
    }
    b.writeln('  Recorded by the shop.');
    b.writeln('  Not verified by Counterbase.');
  } else {
    b.writeln(lr('Paid by', _methodLabel(method)));
    final cash = _cashTender(receipt, method);
    if (cash != null) {
      b.writeln(lr('  Cash given', money(cash.given)));
      b.writeln(lr('  Change', money(cash.change)));
    }
  }
  final ref = (receipt['paymentReference'] ?? '').toString();
  if (ref.isNotEmpty &&
      method != 'SPLIT' &&
      !RecordedPaymentMethod.isRecorded(method)) {
    b.writeln(lr('  Ref', ref.length > 20 ? ref.substring(0, 20) : ref));
  }

  // The amount added to the customer's account at checkout.
  final creditAdded = (receipt['creditAmountAtSale'] as num?)?.toDouble() ?? 0;
  if (creditAdded > 0.01) {
    b.writeln(rule);
    b.writeln(lr('CREDIT ADDED', money(creditAdded)));
    if (receipt['customerName'] != null) {
      b.writeln('  on ${receipt['customerName']}\'s account');
    }
  }

  b.writeln(rule);
  b.writeln(center('Thank you for your purchase!'));
  b.writeln(center('We look forward to'));
  b.writeln(center('serving you again.'));
  b.writeln(center('All the best!'));

  return b.toString().trimRight();
}

/// "Cash given" and "Change" for a cash sale, when the amount handed over was
/// saved with it.
({double given, double change})? _cashTender(
    Map<String, dynamic> receipt, String method) {
  final given = (receipt['cashGiven'] as num?)?.toDouble();
  if (method != 'CASH' || given == null) return null;
  return (
    given: given,
    change: (receipt['changeGiven'] as num?)?.toDouble() ?? 0,
  );
}

String _methodLabel(String method) => switch (method) {
      'CASH' => 'Cash',
      'MPESA' => 'M-Pesa',
      'CARD' => 'Card',
      'CREDIT' => 'Customer credit',
      _ => method,
    };

String _formatDateTime(dynamic dateTime) {
  if (dateTime == null) return 'N/A';
  final dt = dateTime is DateTime
      ? dateTime
      : DateTime.parse(dateTime.toString()).toLocal();
  return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
}

String _formatQuantity(double quantity) => quantity == quantity.roundToDouble()
    ? quantity.toStringAsFixed(0)
    : quantity
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
