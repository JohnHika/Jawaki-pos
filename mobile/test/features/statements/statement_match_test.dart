import 'package:axon_pos/features/statements/domain/statement_match.dart';
import 'package:flutter_test/flutter_test.dart';

RecordedItem item(String code, double amount, {bool bank = false}) =>
    RecordedItem(saleId: code, code: code, amount: amount, isBank: bank);

const statement = '''
SKL4X9Q2TB 2026-11-04 10:37:00 Customer Payment from 0712*** Completed 555.00 8,420.00
SKM2P7R4DA 2026-11-04 12:02:00 Customer Payment from 0733*** Completed 1,200.00 9,620.00
RBC7Y2KLM9 2026-11-04 14:15:00 Customer Payment from 0722*** Completed 2,150.00 11,770.00
''';

void main() {
  test('a code with the same amount next to it is matched', () {
    final result = matchRecorded([item('SKL4X9Q2TB', 555)], statement).single;
    expect(result.status, MatchStatus.matched);
  });

  test('letter case and thousands separators do not matter', () {
    final results = matchRecorded(
      [item('skm2p7r4da', 1200), item('RBC7Y2KLM9', 2150)],
      statement,
    );
    expect(results.map((r) => r.status),
        everyElement(MatchStatus.matched));
  });

  test('a code that is missing is not found', () {
    final result = matchRecorded([item('SKN8Q3V5XC', 2000)], statement).single;
    expect(result.status, MatchStatus.notFound);
  });

  test('a code beside a different amount is flagged, with what was found', () {
    final result = matchRecorded([item('SKL4X9Q2TB', 5550)], statement).single;
    expect(result.status, MatchStatus.amountDiffers);
    expect(result.statementAmounts, contains(555.0));
  });

  test('a neighbour\'s amount is not used', () {
    // 1,200 belongs to SKM2P7R4DA, not to SKL4X9Q2TB.
    final result = matchRecorded([item('SKL4X9Q2TB', 1200)], statement).single;
    expect(result.status, MatchStatus.amountDiffers);
  });

  test('dates and times are not read as amounts', () {
    const text = 'SKL4X9Q2TB 2026-11-04 10:37:00 Completed 9,999.00';
    final result = matchRecorded([item('SKL4X9Q2TB', 4)], text).single;
    expect(result.status, MatchStatus.amountDiffers);
  });

  test('pasted messages work too', () {
    const text =
        'SKL4X9Q2TB Confirmed. Ksh555.00 received from WANJIKU K 0712 678 on 4/11/26 at 10:37 AM.';
    expect(matchRecorded([item('SKL4X9Q2TB', 555)], text).single.status,
        MatchStatus.matched);
  });

  test('an empty statement finds nothing', () {
    expect(matchRecorded([item('SKL4X9Q2TB', 555)], '   ').single.status,
        MatchStatus.notFound);
  });

  test('summary counts each outcome', () {
    final results = matchRecorded([
      item('SKL4X9Q2TB', 555),
      item('SKM2P7R4DA', 1),
      item('SKN8Q3V5XC', 2000),
    ], statement);
    final counts = summarise(results);
    expect(counts.matched, 1);
    expect(counts.differs, 1);
    expect(counts.missing, 1);
  });

  test('a bank reference is matched the same way', () {
    const text = 'FT26308X1 Transfer in 20,000.00 Ref Levisa';
    expect(matchRecorded([item('FT26308X1', 20000, bank: true)], text).single.status,
        MatchStatus.matched);
  });
}
