import 'package:flutter/material.dart';

/// What the phone already knows about the shop, read fresh each time the
/// setup checklist opens. Steps the app can see for itself tick themselves.
class SetupFacts {
  const SetupFacts({
    this.hasReceiptDetails = false,
    this.productCount = 0,
    this.staffCount = 0,
    this.hasPaymentTill = false,
    this.hasLogo = false,
    this.saleCount = 0,
    this.notes = const {},
  });

  final bool hasReceiptDetails;
  final int productCount;
  final int staffCount;
  final bool hasPaymentTill;
  final bool hasLogo;
  final int saleCount;

  /// Steps noted in the shop's database: `DONE` or `SKIPPED`.
  final Map<String, String> notes;
}

enum SetupStatus { todo, done, skipped }

/// Where a step's button takes the owner.
enum SetupAction {
  receiptDetails,
  products,
  staff,
  payments,
  logo,
  sell,
  backup,
}

class SetupStep {
  const SetupStep({
    required this.key,
    required this.title,
    required this.why,
    required this.doneText,
    required this.actionLabel,
    required this.action,
    required this.icon,
    required this.status,
    this.canSkip = true,
  });

  final String key;
  final String title;

  /// One plain sentence on why the step matters.
  final String why;

  /// What the checklist says once the step is done.
  final String doneText;
  final String actionLabel;
  final SetupAction action;
  final IconData icon;
  final SetupStatus status;
  final bool canSkip;

  bool get isOpen => status == SetupStatus.todo;
}

class SetupChecklist {
  SetupChecklist(this.steps);

  final List<SetupStep> steps;

  int get doneCount =>
      steps.where((step) => step.status == SetupStatus.done).length;

  int get openCount => steps.where((step) => step.isOpen).length;

  /// Nothing is left to do: every step is done or put off.
  bool get isFinished => openCount == 0;

  /// The step to suggest first.
  SetupStep? get next {
    for (final step in steps) {
      if (step.isOpen) return step;
    }
    return null;
  }

  /// Steps that are done, so the database can note when each was first
  /// seen done.
  Iterable<String> get doneKeys => steps
      .where((step) => step.status == SetupStatus.done)
      .map((step) => step.key);

  factory SetupChecklist.from(SetupFacts facts) {
    SetupStatus status(String key, bool seenDone) {
      final noted = facts.notes[key];
      if (seenDone || noted == 'DONE') return SetupStatus.done;
      if (noted == 'SKIPPED') return SetupStatus.skipped;
      return SetupStatus.todo;
    }

    String count(int value, String one, String many) =>
        '$value ${value == 1 ? one : many}';

    return SetupChecklist([
      SetupStep(
        key: 'receipt',
        title: 'Put your location and phone on receipts',
        why: 'Customers know where to find you and who to call.',
        doneText: 'Your location and phone print on every receipt.',
        actionLabel: 'Add receipt details',
        action: SetupAction.receiptDetails,
        icon: Icons.storefront_outlined,
        status: status('receipt', facts.hasReceiptDetails),
      ),
      SetupStep(
        key: 'products',
        title: 'Add what you sell',
        why: 'Price each item once, by the piece or by the box.',
        doneText:
            '${count(facts.productCount, 'product', 'products')} ready to sell.',
        actionLabel: 'Add products',
        action: SetupAction.products,
        icon: Icons.inventory_2_outlined,
        status: status('products', facts.productCount > 0),
        canSkip: false,
      ),
      SetupStep(
        key: 'staff',
        title: 'Give each worker their own PIN',
        why: 'Every sale is recorded under the person who made it.',
        doneText:
            '${count(facts.staffCount, 'worker has', 'workers have')} a PIN.',
        actionLabel: 'Add staff',
        action: SetupAction.staff,
        icon: Icons.badge_outlined,
        status: status('staff', facts.staffCount > 0),
      ),
      SetupStep(
        key: 'payments',
        title: 'Add your M-Pesa till or paybill',
        why: 'Customers see where to pay, and staff record the code.',
        doneText: 'Customers can pay into your own till.',
        actionLabel: 'Set up M-Pesa',
        action: SetupAction.payments,
        icon: Icons.phone_iphone_outlined,
        status: status('payments', facts.hasPaymentTill),
      ),
      SetupStep(
        key: 'logo',
        title: 'Add your logo',
        why: 'It goes on receipts and statements in place of ours.',
        doneText: 'Your logo is on receipts and statements.',
        actionLabel: 'Choose logo',
        action: SetupAction.logo,
        icon: Icons.image_outlined,
        status: status('logo', facts.hasLogo),
      ),
      SetupStep(
        key: 'first_sale',
        title: 'Make your first sale',
        why: 'Try one sale and print or share its receipt.',
        doneText: '${count(facts.saleCount, 'sale', 'sales')} made so far.',
        actionLabel: 'Start selling',
        action: SetupAction.sell,
        icon: Icons.point_of_sale_outlined,
        status: status('first_sale', facts.saleCount > 0),
        canSkip: false,
      ),
      SetupStep(
        key: 'backup',
        title: 'Make a backup',
        why: 'Your records live on this phone. A backup keeps them safe if '
            'it is lost.',
        doneText: 'A backup has been made. Make one every week.',
        actionLabel: 'Make a backup',
        action: SetupAction.backup,
        icon: Icons.shield_outlined,
        status: status('backup', false),
        canSkip: false,
      ),
    ]);
  }
}
