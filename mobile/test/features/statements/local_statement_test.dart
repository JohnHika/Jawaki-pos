import 'package:axon_pos/features/statements/domain/local_statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists purchases and payments oldest first with exact totals', () {
    final statement = LocalStatement(
      customerName: 'Mama Njeri',
      customerPhone: '0712345678',
      balance: 450,
      sales: [
        {'total': 300.1, 'paymentMethod': 'CREDIT', 'createdAt': '2026-11-07T10:00:00Z'},
        {'total': 200.2, 'paymentMethod': 'CASH', 'createdAt': '2026-11-01T10:00:00Z'},
        {'total': 150.0, 'paymentMethod': 'credit', 'createdAt': '2026-11-03T10:00:00Z'},
      ],
      payments: [
        {'amount': 0.1, 'paymentMethod': 'CASH', 'collectedAt': '2026-11-08T09:00:00Z'},
      ],
    );

    expect(statement.purchases.map((s) => s['total']), [200.2, 150.0, 300.1]);
    expect(statement.totalBought, 650.3);
    expect(statement.boughtOnCredit, 450.1);
    expect(statement.totalPaidOnAccount, 0.1);
  });

  test('names payment methods in plain words', () {
    expect(statementMethodLabel('MPESA_RECORDED'), 'M-Pesa (recorded)');
    expect(statementMethodLabel('CREDIT'), 'On credit');
    expect(statementMethodLabel(null), 'Not recorded');
    expect(statementMethodLabel('VOUCHER'), 'VOUCHER');
  });
}
