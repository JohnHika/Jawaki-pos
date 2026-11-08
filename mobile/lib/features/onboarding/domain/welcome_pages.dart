import 'package:flutter/material.dart';

import '../../../core/auth/app_roles.dart';

class WelcomePage {
  const WelcomePage({
    required this.icon,
    required this.title,
    required this.body,
    this.points = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
}

/// The welcome tour for one person. Each page covers work they can do, so a
/// cashier is not told about expenses they cannot open.
List<WelcomePage> welcomePagesFor({
  required String shopName,
  required String firstName,
  required RolePermissions permissions,
  required bool isOwner,
}) {
  final shop = shopName.trim().isEmpty ? 'your shop' : shopName.trim();
  final name = firstName.trim();
  return [
    WelcomePage(
      icon: Icons.waving_hand_outlined,
      title: name.isEmpty ? 'Karibu' : 'Karibu, $name',
      body: 'This is where $shop keeps its sales, stock and customers. '
          'Everything is saved on this phone, and it works without internet.',
    ),
    if (permissions.canMakeSales || permissions.canSeePOS)
      const WelcomePage(
        icon: Icons.point_of_sale_outlined,
        title: 'Sell in a few taps',
        body: 'Most of the day happens on the Sell screen.',
        points: [
          'Tap the products, then Pay.',
          'Type the cash the customer gives. The app shows the change.',
          'Every receipt shows your location, the customer and the time. '
              'Find it again under Receipts to share or print.',
        ],
      ),
    if (permissions.canSeeCustomers)
      const WelcomePage(
        icon: Icons.people_outline,
        title: 'Customers who pay later',
        body: 'Keep track of who owes what.',
        points: [
          'Save each customer with their name and phone.',
          'Sell on credit, then record what they pay back in cash, '
              'M-Pesa or bank.',
          'Send a statement as a PDF, a spreadsheet or a short message.',
        ],
      ),
    if (permissions.canSeeInventory)
      const WelcomePage(
        icon: Icons.inventory_2_outlined,
        title: 'Stock that counts itself',
        body: 'Each sale takes the items off your stock.',
        points: [
          'Sell by the piece or by the box.',
          'Receive deliveries when they arrive.',
          'Count the shelves to find what is missing.',
        ],
      ),
    if (permissions.canViewFinance)
      const WelcomePage(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Know what you made today',
        body: 'Money in and money out, in one place.',
        points: [
          'Record what you pay from the till, like transport or rent.',
          'Expenses shows what is left from the day\'s sales.',
          'At End of day, count the cash. The app tells you if any is '
              'missing.',
        ],
      ),
    isOwner
        ? const WelcomePage(
            icon: Icons.shield_outlined,
            title: 'Your records stay yours',
            body: 'Nothing leaves this phone unless you send it.',
            points: [
              'Each worker signs in with their own PIN.',
              'Make a backup every week from Settings.',
              'The User guide in Settings answers most questions.',
            ],
          )
        : const WelcomePage(
            icon: Icons.pin_outlined,
            title: 'Your PIN, your sales',
            body: 'Every sale is recorded under the person who made it.',
            points: [
              'Sign in with your own PIN and keep it to yourself.',
              'Lock the app when you step away from the counter.',
              'Ask the owner if you need to see more of the app.',
            ],
          ),
  ];
}
