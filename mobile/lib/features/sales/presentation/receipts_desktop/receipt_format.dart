import 'package:flutter/material.dart';

import '../../../../core/theme/design_system.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "10 Nov, 14:32", with the year added when it is not this year.
String formatReceiptTime(DateTime dt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  final year = dt.year == today.year ? '' : ' ${dt.year}';
  return '${dt.day} ${_months[dt.month - 1]}$year, $hour:$minute';
}

/// "10 Nov 2026" for headings and range labels.
String formatReceiptDay(DateTime dt) =>
    '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

/// Upper-case code with no spaces: "M-Pesa" and "MPESA" compare equal.
String receiptMethodKey(String method) =>
    method.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

/// The colour a payment method carries across the app.
Color receiptMethodColor(String method) {
  switch (receiptMethodKey(method)) {
    case 'CASH':
      return DesignColors.cash;
    case 'MPESA':
      return DesignColors.mpesa;
    case 'CARD':
    case 'CREDIT':
      return DesignColors.credit;
    case 'PESAPAL':
      return DesignColors.pesapal;
    case 'TOURISTTAP':
      return DesignColors.touristtap;
    case 'MPESARECORDED':
    case 'BANKRECORDED':
      return DesignColors.warning;
    default:
      return DesignColors.brand;
  }
}

/// A receipt with this status was cancelled.
bool isVoidedStatus(String? status) =>
    (status ?? '').toString().toUpperCase() == 'VOIDED';

/// Red for text and icons: the bright error colour is too faint on the light
/// page, so light mode gets a deeper shade.
Color receiptDangerColor(bool dark) =>
    dark ? DesignColors.error : const Color(0xFFB3261E);
