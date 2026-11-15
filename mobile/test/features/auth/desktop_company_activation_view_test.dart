import 'package:axon_pos/features/auth/presentation/desktop/company_activation_desktop_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

Widget _view({
  bool hasCheckout = false,
  bool loading = false,
  String? error,
  VoidCallback? onPay,
  VoidCallback? onVerify,
}) =>
    CompanyActivationDesktopView(
      priceLabel: 'KSh 35,000',
      companyName: 'Njeri Hardware',
      hasCheckout: hasCheckout,
      loading: loading,
      error: error,
      codeCard: const Align(
        alignment: Alignment.centerLeft,
        child: Text('Have a referral or promo code?'),
      ),
      onPay: onPay ?? () {},
      onVerify: onVerify ?? () {},
      onSwitchAccount: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('desktop-activation', () => _view());
  shotMatrix(
    'desktop-activation-checkout',
    () => _view(
      hasCheckout: true,
      error: 'Payment is still being confirmed. Please wait a moment and try again.',
    ),
  );

  testWidgets('pay, then check status once a checkout link exists',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var paid = 0;
    var verified = 0;
    await tester.pumpWidget(desktopApp(_view(onPay: () => paid++)));
    await tester.pumpAndSettle();
    expect(find.text('Pay KSh 35,000 to activate'), findsOneWidget);
    expect(find.textContaining('check status'), findsNothing);
    await tester.tap(find.text('Pay KSh 35,000 to activate'));
    expect(paid, 1);

    await tester.pumpWidget(desktopApp(
      _view(hasCheckout: true, onVerify: () => verified++),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Open payment checkout again'), findsOneWidget);
    await tester.tap(find.textContaining('check status'));
    expect(verified, 1);
  });
}
