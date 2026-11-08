import 'package:flutter/material.dart';

/// What a shop pays for apart from stock. Stock that comes in goes through
/// Receive stock, so it is never counted twice.
class ExpenseCategory {
  const ExpenseCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

const kExpenseCategories = <ExpenseCategory>[
  ExpenseCategory('Rent', Icons.storefront_outlined),
  ExpenseCategory('Wages', Icons.badge_outlined),
  ExpenseCategory('Transport', Icons.local_shipping_outlined),
  ExpenseCategory('Electricity and water', Icons.bolt_outlined),
  ExpenseCategory('Airtime and internet', Icons.wifi_rounded),
  ExpenseCategory('Shop supplies', Icons.cleaning_services_outlined),
  ExpenseCategory('Repairs', Icons.build_outlined),
  ExpenseCategory('Licences and fees', Icons.description_outlined),
  ExpenseCategory('Other', Icons.more_horiz_rounded),
];

IconData expenseIcon(String category) {
  for (final item in kExpenseCategories) {
    if (item.label == category) return item.icon;
  }
  return Icons.more_horiz_rounded;
}

/// How an expense was paid. Only cash leaves the till.
const kExpenseMethods = <({String code, String label})>[
  (code: 'CASH', label: 'Cash from the till'),
  (code: 'MPESA', label: 'M-Pesa'),
  (code: 'BANK', label: 'Bank'),
];

String expenseMethodLabel(String code) => switch (code.toUpperCase()) {
      'MPESA' => 'M-Pesa',
      'BANK' => 'Bank',
      _ => 'Cash',
    };

enum ExpensePeriod { today, week, month }

extension ExpensePeriodText on ExpensePeriod {
  String get label => switch (this) {
        ExpensePeriod.today => 'Today',
        ExpensePeriod.week => 'This week',
        ExpensePeriod.month => 'This month',
      };
}

/// The days a period covers, from midnight at the start to midnight after
/// [now]. Weeks start on Monday.
({DateTime from, DateTime to}) expensePeriodRange(
  ExpensePeriod period,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final to = today.add(const Duration(days: 1));
  return switch (period) {
    ExpensePeriod.today => (from: today, to: to),
    ExpensePeriod.week => (
        from: today.subtract(Duration(days: today.weekday - DateTime.monday)),
        to: to,
      ),
    ExpensePeriod.month => (from: DateTime(now.year, now.month), to: to),
  };
}

/// Sales set against what was spent, worked out in cents so the figures add
/// up exactly.
class ExpenseSummary {
  ExpenseSummary._(this._salesCents, this._expenseCents, this.byCategory);

  factory ExpenseSummary.from({
    required double sales,
    required List<Map<String, dynamic>> expenses,
  }) {
    var spent = 0;
    final perCategory = <String, int>{};
    for (final expense in expenses) {
      final cents = ((expense['amount'] as num).toDouble() * 100).round();
      spent += cents;
      final category = expense['category'] as String;
      perCategory.update(category, (v) => v + cents, ifAbsent: () => cents);
    }
    final sorted = perCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ExpenseSummary._(
      (sales * 100).round(),
      spent,
      [for (final e in sorted) (category: e.key, amount: e.value / 100)],
    );
  }

  final int _salesCents;
  final int _expenseCents;

  /// Biggest first.
  final List<({String category, double amount})> byCategory;

  double get sales => _salesCents / 100;
  double get expenses => _expenseCents / 100;
  double get left => (_salesCents - _expenseCents) / 100;

  /// Share of sales spent, 0 to 1, or null with no sales.
  double? get spentShare =>
      _salesCents <= 0 ? null : (_expenseCents / _salesCents).clamp(0, 1);
}
