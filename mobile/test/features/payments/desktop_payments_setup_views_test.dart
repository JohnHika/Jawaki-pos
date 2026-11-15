import 'package:axon_pos/core/theme/design_system.dart';
import 'package:axon_pos/features/dashboard/presentation/desktop/desktop_bar_chart.dart';
import 'package:axon_pos/features/payments/presentation/desktop/desktop_payment_analytics_view.dart';
import 'package:axon_pos/features/payments/presentation/desktop/desktop_payout_setup_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

const _banks = [
  DesktopBank(code: '01', name: 'Equity Bank'),
  DesktopBank(code: '02', name: 'KCB Bank'),
  DesktopBank(code: '03', name: 'Co-operative Bank'),
];

DesktopPayoutSetupView _payout({
  DesktopPayoutStatus status = DesktopPayoutStatus.needed,
  bool changing = false,
  String? bankCode,
  String? error,
  String? accountLoadError,
  VoidCallback? onSave,
  VoidCallback? onChange,
}) =>
    DesktopPayoutSetupView(
      status: status,
      banks: _banks,
      bankCode: bankCode,
      accountController: TextEditingController(),
      ownsAccount: false,
      acceptedTerms: false,
      termsLabel: const Text('I agree to the merchant payment terms.'),
      termsLink: const Text('Read merchant payment terms'),
      changing: changing,
      saving: false,
      canSave: true,
      onBank: (_) {},
      onOwnsAccount: (_) {},
      onAcceptedTerms: (_) {},
      onSave: onSave ?? () {},
      onRefresh: () {},
      savedBankName: 'Equity Bank',
      savedLast4: '4821',
      savedHolder: 'Mwangi General Store',
      error: error,
      accountLoadError: accountLoadError,
      onChange: onChange,
      onCancelChange: () {},
      onDone: () {},
    );

DesktopPaymentAnalyticsView _analytics({
  bool empty = false,
  String? error,
  bool local = false,
}) =>
    DesktopPaymentAnalyticsView(
      periods: const ['Today', 'This Week', 'This Month'],
      selectedPeriod: 0,
      onPeriod: (_) {},
      totalAmount: empty ? 0 : 84300,
      transactionCount: empty ? 0 : 61,
      averagePayment: empty ? 0 : 1382,
      methods: empty
          ? const []
          : const [
              DesktopPayMethod(
                  label: 'Cash', count: 30, total: 41200, color: DesignColors.cash),
              DesktopPayMethod(
                  label: 'M-Pesa', count: 26, total: 37100, color: DesignColors.mpesa),
              DesktopPayMethod(
                  label: 'Card', count: 5, total: 6000, color: DesignColors.credit),
            ],
      trend: [
        for (var h = 8; h < 20; h++)
          DesktopChartBar(
            label: '$h:00',
            value: (h * 37 % 11 + 1) * 900.0,
            tooltipTitle: '$h:00',
            tooltipValue: 'KES 3,000 · 4 transactions',
          ),
      ],
      peakHours: const [
        DesktopPayHour(hour: 9, count: 8, total: 12400),
        DesktopPayHour(hour: 13, count: 12, total: 18900),
        DesktopPayHour(hour: 17, count: 15, total: 22100),
        DesktopPayHour(hour: 18, count: 9, total: 11000),
      ],
      onRefresh: () {},
      errorMessage: error,
      localNotice:
          local ? 'Offline: showing sales saved on this computer.' : null,
    );

void main() {
  setUpAll(loadShotFonts);

  group('Customer payments setup', () {
    shotMatrix('payout-needed', () => _payout(bankCode: '01'));
    shotMatrix(
      'payout-verified',
      () => _payout(status: DesktopPayoutStatus.verified, bankCode: '01'),
    );
    shotMatrix(
      'payout-pending-error',
      () => _payout(
        status: DesktopPayoutStatus.pending,
        accountLoadError: 'The connection dropped.',
      ),
    );

    testWidgets('a saved account shows its details and can be changed',
        (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      var changed = 0;
      await tester.pumpWidget(desktopApp(_payout(
        status: DesktopPayoutStatus.verified,
        bankCode: '01',
        onChange: () => changed++,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Equity Bank'), findsOneWidget);
      expect(find.text('•••• 4821'), findsOneWidget);
      await tester.tap(find.text('Change payout details'));
      expect(changed, 1);
    });

    testWidgets('connecting an account saves from the button', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      var saved = 0;
      await tester.pumpWidget(desktopApp(_payout(onSave: () => saved++)));
      await tester.pumpAndSettle();
      expect(find.text('Connect payout account'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Connect payout account'));
      expect(saved, 1);
    });
  });

  group('Payment analytics', () {
    shotMatrix('payment-analytics', () => _analytics(local: true));
    shotMatrix('payment-analytics-empty', () => _analytics(empty: true));
    shotMatrix('payment-analytics-error', () => _analytics(error: 'Offline.'));

    testWidgets('shows the figures and both tables', (tester) async {
      useWindow(tester, desktopSizes['1366']!);
      await tester.pumpWidget(desktopApp(_analytics()));
      await tester.pumpAndSettle();
      expect(find.text('Total payments'), findsOneWidget);
      expect(find.text('M-Pesa'), findsOneWidget);
      expect(find.text('5:00 PM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
