import 'dart:convert';

/// A short, plain-words suggestion shown on Home for the kind of shop the
/// owner chose. [path] is an app route the suggestion opens.
class ShopTip {
  const ShopTip({
    required this.title,
    required this.body,
    required this.path,
    required this.action,
  });

  final String title;
  final String body;
  final String path;
  final String action;
}

/// Something that changed in the app itself, shown to every shop.
class WhatsNew {
  const WhatsNew({required this.title, required this.body, this.path});

  final String title;
  final String body;
  final String? path;
}

/// What changed in the app, newest first. Kept on the device so Home works
/// with no connection.
const List<WhatsNew> kWhatsNew = [
  WhatsNew(
    title: 'Pay several suppliers in one go',
    body:
        'In Finance, under Suppliers, tick the bills you are paying and record them together, in cash or by M-Pesa.',
    path: '/finance',
  ),
  WhatsNew(
    title: 'See what is left after expenses',
    body:
        'Record rent, transport and other spending. End of day takes cash expenses off the till.',
    path: '/expenses',
  ),
  WhatsNew(
    title: 'Cash given and change on receipts',
    body:
        'Receipts also show your location, phone and the customer. Set them in Settings, under Receipt details.',
  ),
  WhatsNew(
    title: 'Customer statements to share',
    body:
        'Open a customer and tap Customer statement for a PDF, a spreadsheet or a short message.',
    path: '/customers',
  ),
  WhatsNew(
    title: 'Record M-Pesa paid to your own till',
    body:
        'Paste the message at checkout. Counterbase reads the code and amount, and a code works on one sale only.',
    path: '/settings/recorded-payments',
  ),
  WhatsNew(
    title: 'A shared phone shows who is at the till',
    body: 'Staff pick their name, then enter their own PIN.',
  ),
  WhatsNew(
    title: 'Clearer sign-in and setup',
    body: 'Your shop name and logo show on every sign-in screen.',
  ),
];

const ShopTip _lowStock = ShopTip(
  title: 'Set a low-stock level',
  body: 'You get a warning before a fast seller runs out.',
  path: '/inventory',
  action: 'Open stock',
);

const ShopTip _countStock = ShopTip(
  title: 'Count a shelf each week',
  body: 'A short stock count finds missing items while it is still small.',
  path: '/stock-counts',
  action: 'Start a count',
);

const ShopTip _customerCredit = ShopTip(
  title: 'Keep credit sales on a name',
  body: 'Attach the customer so you can see who owes what.',
  path: '/customers',
  action: 'Open customers',
);

const ShopTip _priceList = ShopTip(
  title: 'Keep one price list',
  body: 'Change a price once and every till uses it.',
  path: '/price-list',
  action: 'Open price list',
);

const ShopTip _reports = ShopTip(
  title: 'Look at your best sellers',
  body: 'Stock more of what sells and less of what sits.',
  path: '/reports',
  action: 'Open reports',
);

const Map<String, List<ShopTip>> _tipsByProfile = {
  'general_retail': [_lowStock, _reports],
  'grocery': [
    ShopTip(
      title: 'Watch fast movers',
      body: 'Sugar, flour, oil and bread go first. Set low-stock levels on them.',
      path: '/inventory',
      action: 'Open stock',
    ),
    _countStock,
  ],
  'cafe_takeaway': [
    ShopTip(
      title: 'Use favourites for the menu',
      body: 'Pin your top ten items so a rush order takes two taps.',
      path: '/',
      action: 'Open Sell',
    ),
    _reports,
  ],
  'bakery_food_counter': [
    ShopTip(
      title: 'Count what is left at closing',
      body: 'A quick count shows what you baked but did not sell.',
      path: '/stock-counts',
      action: 'Start a count',
    ),
    _reports,
  ],
  'market_stall': [
    ShopTip(
      title: 'Record M-Pesa as it arrives',
      body: 'Paste each message at checkout so none goes missing.',
      path: '/settings/recorded-payments',
      action: 'Recorded payments',
    ),
    _lowStock,
  ],
  'fashion': [
    ShopTip(
      title: 'Add size and colour to products',
      body: 'Then you know which sizes sold out.',
      path: '/products',
      action: 'Open products',
    ),
    _reports,
  ],
  'electronics': [
    ShopTip(
      title: 'Add the serial number or model',
      body: 'Handy when a customer returns with a receipt.',
      path: '/products',
      action: 'Open products',
    ),
    _customerCredit,
  ],
  'hardware': [
    ShopTip(
      title: 'Sell by the unit that fits',
      body: 'Bag, metre, kilogram or piece. Choose it on each product.',
      path: '/products',
      action: 'Open products',
    ),
    _customerCredit,
  ],
  'beauty': [
    ShopTip(
      title: 'Keep a list of regulars',
      body: 'Add customers so repeat buyers are easy to find.',
      path: '/customers',
      action: 'Open customers',
    ),
    _lowStock,
  ],
  'wholesale': [
    _customerCredit,
    _priceList,
  ],
  'stationery': [_lowStock, _countStock],
  'auto_parts': [
    ShopTip(
      title: 'Add the part number',
      body: 'Search by part number at the counter.',
      path: '/products',
      action: 'Open products',
    ),
    _customerCredit,
  ],
  'pharmacy_retail': [
    ShopTip(
      title: 'Record batch and expiry',
      body: 'Sell the oldest stock first and avoid expired items.',
      path: '/inventory',
      action: 'Open stock',
    ),
    _countStock,
  ],
  'agrovet': [
    ShopTip(
      title: 'Record batch and expiry',
      body: 'Seeds, feeds and medicines expire. Check them each month.',
      path: '/inventory',
      action: 'Open stock',
    ),
    _customerCredit,
  ],
  'butchery': [
    ShopTip(
      title: 'Sell by weight',
      body: 'Allow decimals on meat products so a sale matches the scale.',
      path: '/products',
      action: 'Open products',
    ),
    _countStock,
  ],
  'beverages': [
    ShopTip(
      title: 'Count crates and bottles',
      body: 'A weekly count catches breakage and loss.',
      path: '/stock-counts',
      action: 'Start a count',
    ),
    _lowStock,
  ],
  'bookshop': [_priceList, _lowStock],
  'kamukunji_counter': [_priceList, _customerCredit],
  'service_counter': [
    ShopTip(
      title: 'List your services as products',
      body: 'Then each service shows in sales and reports.',
      path: '/products',
      action: 'Open products',
    ),
    _customerCredit,
  ],
};

/// Suggestions for the shop type the owner chose. Always returns at least
/// two, so a custom or unknown layout still gets useful ones.
List<ShopTip> tipsForProfile(String profileId) =>
    _tipsByProfile[profileId] ?? const [_lowStock, _reports];

/// Today's takings by how the money arrived.
class TakingsSplit {
  const TakingsSplit({
    this.cash = 0,
    this.recorded = 0,
    this.credit = 0,
    this.other = 0,
    this.recordedCount = 0,
  });

  final double cash;
  final double recorded;
  final double credit;

  /// Anything else, such as a payment the provider confirmed.
  final double other;

  /// Number of sales with a recorded part, for the end of day reminder.
  final int recordedCount;

  double get total => cash + recorded + credit + other;
}

const _notSales = {'VOIDED', 'REFUNDED', 'FAILED', 'CANCELLED'};

enum _Group { cash, recorded, credit, other }

_Group _groupFor(String method) {
  switch (method.toUpperCase()) {
    case 'CASH':
      return _Group.cash;
    case 'MPESA_RECORDED':
    case 'BANK_RECORDED':
      return _Group.recorded;
    case 'CREDIT':
      return _Group.credit;
    default:
      return _Group.other;
  }
}

/// Adds up today's sales by money group. Voided and refunded sales are left
/// out. A split sale is divided by its parts when they can be read; if they
/// cannot, the whole amount goes to "other" so the total still matches.
TakingsSplit splitTakings(
  Iterable<({String method, String? reference, double total, String status})>
      sales,
) {
  final totals = {for (final g in _Group.values) g: 0.0};
  var recordedCount = 0;

  for (final sale in sales) {
    if (_notSales.contains(sale.status.toUpperCase())) continue;
    if (!sale.total.isFinite || sale.total <= 0) continue;

    final method = sale.method.toUpperCase();
    if (method == 'SPLIT') {
      final parts = _readParts(sale.reference);
      final sum = parts.fold<double>(0, (a, p) => a + p.amount);
      if (parts.isNotEmpty && (sum - sale.total).abs() < 0.01) {
        var hasRecorded = false;
        for (final part in parts) {
          final group = _groupFor(part.method);
          totals[group] = totals[group]! + part.amount;
          if (group == _Group.recorded) hasRecorded = true;
        }
        if (hasRecorded) recordedCount++;
        continue;
      }
      totals[_Group.other] = totals[_Group.other]! + sale.total;
      continue;
    }

    final group = _groupFor(method);
    totals[group] = totals[group]! + sale.total;
    if (group == _Group.recorded) recordedCount++;
  }

  return TakingsSplit(
    cash: totals[_Group.cash]!,
    recorded: totals[_Group.recorded]!,
    credit: totals[_Group.credit]!,
    other: totals[_Group.other]!,
    recordedCount: recordedCount,
  );
}

List<({String method, double amount})> _readParts(String? reference) {
  if (reference == null || reference.isEmpty) return const [];
  try {
    final decoded = jsonDecode(reference);
    if (decoded is! List) return const [];
    final parts = <({String method, double amount})>[];
    for (final item in decoded) {
      if (item is! Map) return const [];
      final raw = item['amount'];
      final amount =
          raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
      if (amount == null || !amount.isFinite || amount <= 0) return const [];
      parts.add((method: (item['method'] ?? '').toString(), amount: amount));
    }
    return parts;
  } catch (_) {
    return const [];
  }
}
