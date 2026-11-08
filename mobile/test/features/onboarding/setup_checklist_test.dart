import 'package:axon_pos/core/auth/app_roles.dart';
import 'package:axon_pos/core/auth/local_staff_roles.dart';
import 'package:axon_pos/features/onboarding/domain/setup_checklist.dart';
import 'package:axon_pos/features/onboarding/domain/welcome_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setup checklist', () {
    test('a new shop starts with receipt details', () {
      final list = SetupChecklist.from(const SetupFacts());

      expect(list.doneCount, 0);
      expect(list.isFinished, isFalse);
      expect(list.next?.key, 'receipt');
    });

    test('steps the phone can see tick themselves', () {
      final list = SetupChecklist.from(const SetupFacts(
        hasReceiptDetails: true,
        productCount: 12,
        saleCount: 1,
      ));

      expect(list.doneKeys, ['receipt', 'products', 'first_sale']);
      expect(list.next?.key, 'staff');
      expect(
        list.steps.firstWhere((s) => s.key == 'products').doneText,
        '12 products ready to sell.',
      );
    });

    test('put-off steps no longer hold up the shop', () {
      final list = SetupChecklist.from(const SetupFacts(
        hasReceiptDetails: true,
        productCount: 1,
        saleCount: 3,
        notes: {
          'staff': 'SKIPPED',
          'payments': 'SKIPPED',
          'logo': 'SKIPPED',
          'backup': 'DONE',
        },
      ));

      expect(list.isFinished, isTrue);
      expect(list.next, isNull);
      expect(list.doneCount, 4);
    });

    test('the steps that matter most cannot be put off', () {
      final list = SetupChecklist.from(const SetupFacts());
      final required =
          list.steps.where((step) => !step.canSkip).map((step) => step.key);

      expect(required, ['products', 'first_sale', 'backup']);
    });
  });

  group('welcome pages', () {
    test('the owner hears about every part of the shop', () {
      final pages = welcomePagesFor(
        shopName: 'Levisa Ventures',
        firstName: 'Mathias',
        permissions: RolePermissions(const [
          'sales.create',
          'customers.view',
          'inventory.stock.view',
          'finance.view',
        ]),
        isOwner: true,
      );

      expect(pages.first.title, 'Karibu, Mathias');
      expect(pages.first.body, contains('Levisa Ventures'));
      expect(pages.last.title, 'Your records stay yours');
    });

    test('a cashier is not told about areas they cannot open', () {
      final pages = welcomePagesFor(
        shopName: 'Levisa Ventures',
        firstName: '',
        permissions: RolePermissions(const ['sales.create']),
        isOwner: false,
      );
      final titles = pages.map((page) => page.title).toList();

      expect(titles.first, 'Karibu');
      expect(titles, contains('Sell in a few taps'));
      expect(titles, isNot(contains('Know what you made today')));
      expect(titles.last, 'Your PIN, your work');
    });
  });

  group('welcome pages for each staff role', () {
    List<WelcomePage> pagesFor(String role) => welcomePagesFor(
          shopName: 'Levisa Ventures',
          firstName: 'Achieng',
          permissions: RolePermissions(LocalStaffRoles.permissionsFor(role)),
          isOwner: false,
        );
    List<String> allText(List<WelcomePage> pages) => [
          for (final page in pages) ...[page.title, page.body, ...page.points],
        ];

    test('a cashier learns to sell and is not told about money or counts', () {
      final pages = pagesFor('Cashier');

      expect(pages.map((p) => p.title), [
        'Karibu, Achieng',
        'Sell in a few taps',
        'Customers who pay later',
        'Stock that counts itself',
        'Your PIN, your work',
      ]);
      final text = allText(pages).join(' ');
      expect(text, contains('See what is left in Products'));
      expect(text, isNot(contains('Receive deliveries')));
      expect(text, isNot(contains('record what they pay back')));
    });

    test('a store manager also hears about stock work and expenses', () {
      final pages = pagesFor('Manager');

      expect(pages.map((p) => p.title), [
        'Karibu, Achieng',
        'Sell in a few taps',
        'Customers who pay later',
        'Stock that counts itself',
        'Know what you made today',
        'Your PIN, your work',
      ]);
      final text = allText(pages).join(' ');
      expect(text, contains('Receive deliveries in Products'));
      expect(text, contains('Count the shelves'));
      expect(text, contains('Record what you pay from the till'));
    });

    test('a stock keeper is not shown the Sell screen', () {
      expect(pagesFor('Stock keeper').map((p) => p.title), [
        'Karibu, Achieng',
        'Stock that counts itself',
        'Your PIN, your work',
      ]);
    });
  });
}
