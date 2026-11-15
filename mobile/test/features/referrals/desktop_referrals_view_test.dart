import 'package:axon_pos/features/referrals/presentation/desktop/desktop_referrals_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/desktop_harness.dart';
import '../../support/shot.dart';

Widget _view({
  List<DesktopReferral>? referrals,
  Future<DesktopRedeemResult> Function(String)? onRedeem,
  VoidCallback? onCopyInvite,
  VoidCallback? onCopyCode,
}) =>
    DesktopReferralsView(
      title: 'Invite Shops',
      code: 'MAMA-4821',
      referredDays: 14,
      referrerDays: 30,
      rewarded: 2,
      pending: 1,
      daysEarned: 60,
      referrals: referrals ??
          const [
            DesktopReferral(name: 'Wanjiku Mini Mart', rewarded: true, daysEarned: 30),
            DesktopReferral(name: 'Otieno Hardware', rewarded: true, daysEarned: 30),
            DesktopReferral(name: 'Karen Fresh Greens', rewarded: false, daysEarned: 0),
          ],
      onCopyCode: onCopyCode ?? () {},
      onCopyInvite: onCopyInvite ?? () {},
      onRedeem: onRedeem ??
          (_) async => const DesktopRedeemResult(ok: true, message: 'Done.'),
      onRefresh: () {},
    );

void main() {
  setUpAll(loadShotFonts);

  shotMatrix('referrals', () => _view());
  shotMatrix('referrals-empty', () => _view(referrals: const []));

  testWidgets('copy buttons hand back to the screen', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    var invite = 0;
    var code = 0;
    await tester.pumpWidget(desktopApp(_view(
      onCopyInvite: () => invite++,
      onCopyCode: () => code++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('referral-copy-invite')));
    await tester.tap(find.byKey(const ValueKey('referral-copy-code')));
    expect(invite, 1);
    expect(code, 1);
  });

  testWidgets('Enter in the code box redeems and shows the answer',
      (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    String? sent;
    await tester.pumpWidget(desktopApp(_view(onRedeem: (c) async {
      sent = c;
      return const DesktopRedeemResult(ok: false, message: 'That code is not valid.');
    })));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('referral-redeem-field')), 'promo10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(sent, 'promo10');
    expect(find.text('That code is not valid.'), findsOneWidget);
  });

  testWidgets('a good code clears the box', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('referral-redeem-field')), 'WELCOME');
    await tester.tap(find.byKey(const ValueKey('referral-redeem-button')));
    await tester.pumpAndSettle();
    expect(find.text('Done.'), findsOneWidget);
    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('referral-redeem-field')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('no invited shops shows the empty state', (tester) async {
    useWindow(tester, desktopSizes['1366']!);
    await tester.pumpWidget(desktopApp(_view(referrals: const [])));
    await tester.pumpAndSettle();
    expect(find.text('No shops invited yet'), findsOneWidget);
  });
}
