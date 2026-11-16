import 'package:axon_pos/core/utils/kra_pin.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _user(Map<String, dynamic> settings) => {
      'tenant': {'settings': settings},
    };

void main() {
  test('a PIN is a letter, nine digits and a letter', () {
    expect(KraPin.isValid('A123456789B'), isTrue);
    expect(KraPin.isValid(' p051234567z '), isTrue);
    expect(KraPin.isValid('123456789'), isFalse);
    expect(KraPin.isValid('A12345678B'), isFalse);
    expect(KraPin.isValid(''), isFalse);
    expect(KraPin.normalize(' a123 456789 b '), 'A123456789B');
  });

  test('it prints only when saved, valid and switched on', () {
    expect(KraPin.forReceipt(null), isNull);
    expect(KraPin.forReceipt(_user({})), isNull);
    // Saved but not switched on: the owner chose not to print it.
    expect(KraPin.forReceipt(_user({'kraPin': 'A123456789B'})), isNull);
    expect(
      KraPin.forReceipt(_user({
        'kraPin': 'A123456789B',
        'showKraPinOnReceipts': false,
      })),
      isNull,
    );
    expect(
      KraPin.forReceipt(_user({
        'kraPin': 'a123456789b',
        'showKraPinOnReceipts': true,
      })),
      'A123456789B',
    );
    // Switched on but not a real PIN: nothing is printed.
    expect(
      KraPin.forReceipt(_user({
        'kraPin': 'oops',
        'showKraPinOnReceipts': true,
      })),
      isNull,
    );
  });
}
