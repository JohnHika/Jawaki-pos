import 'package:flutter_test/flutter_test.dart';
import 'package:axon_pos/features/pricelist/domain/price_list_builder.dart';

void main() {
  final date = DateTime(2026, 10, 24);

  const sufuria = PriceListItem(
    name: 'Sufuria 24cm',
    unit: 'piece',
    price: 450,
    categoryName: 'Kitchenware',
    tiers: [
      PriceTierLine(unit: 'Dozen', quantityPerUnit: 12, price: 4800),
    ],
  );
  const plate = PriceListItem(
    name: 'Plate',
    unit: 'piece',
    price: 120.5,
    categoryName: 'Kitchenware',
  );
  const bucket = PriceListItem(
    name: 'Bucket',
    unit: 'piece',
    price: 300,
    categoryName: 'Plastics',
  );
  const loose = PriceListItem(
    name: 'Rice',
    unit: 'kg',
    price: 1500,
    categoryName: '',
  );

  group('priceKes', () {
    test('separates thousands and drops cents when whole', () {
      expect(priceKes(450), 'KES 450');
      expect(priceKes(12500), 'KES 12,500');
      expect(priceKes(1234567), 'KES 1,234,567');
    });

    test('keeps cents when there are some', () {
      expect(priceKes(120.5), 'KES 120.50');
    });
  });

  group('groupPriceList', () {
    test('orders categories A to Z with Other last, items A to Z', () {
      final groups = groupPriceList([loose, sufuria, bucket, plate]);
      expect(groups.keys.toList(), ['Kitchenware', 'Plastics', 'Other']);
      expect(groups['Kitchenware']!.map((i) => i.name).toList(),
          ['Plate', 'Sufuria 24cm']);
    });
  });

  group('buildPriceListText', () {
    test('writes a WhatsApp-ready list with bulk prices and a contact line', () {
      final text = buildPriceListText(
        shopName: 'Kamau Imports',
        date: date,
        items: [sufuria, plate, bucket],
        phone: '0712 345 678',
      );
      expect(text, '''*Kamau Imports*
Price list · 24 Oct 2026

*Kitchenware*
• Plate: KES 120.50
• Sufuria 24cm: KES 450
    Dozen (12): KES 4,800

*Plastics*
• Bucket: KES 300

Call or WhatsApp 0712 345 678''');
    });

    test('names the unit when it is not a piece', () {
      final text = buildPriceListText(
          shopName: 'Shop', date: date, items: [loose]);
      expect(text.contains('• Rice: KES 1,500 per kg'), isTrue);
      expect(text.contains('*Other*'), isTrue);
    });

    test('can leave bulk prices out', () {
      final text = buildPriceListText(
          shopName: 'Shop', date: date, items: [sufuria], showTiers: false);
      expect(text.contains('Dozen'), isFalse);
    });

    test('says so when nothing is selected', () {
      final text =
          buildPriceListText(shopName: 'Shop', date: date, items: const []);
      expect(text.contains('No items selected.'), isTrue);
    });
  });
}
