import 'package:axon_pos/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product grid keeps two columns on phones and grows on tablets', () {
    expect(productGridColumns(360), 2);
    expect(productGridColumns(411), 2);
    expect(productGridColumns(600), 3);
    expect(productGridColumns(800), 4);
    expect(productGridColumns(1400), 6);
    expect(productGridColumns(120), 2);
  });
}
