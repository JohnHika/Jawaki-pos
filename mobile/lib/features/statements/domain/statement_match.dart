/// One payment the shop recorded itself, as the owner checks it against their
/// own M-Pesa or bank statement.
class RecordedItem {
  const RecordedItem({
    required this.saleId,
    required this.code,
    required this.amount,
    required this.isBank,
  });

  final String saleId;
  final String code;
  final double amount;
  final bool isBank;
}

enum MatchStatus {
  /// The code is in the statement and the amount agrees.
  matched,

  /// The code is in the statement but next to a different amount.
  amountDiffers,

  /// The code is not in the statement at all.
  notFound,
}

class MatchResult {
  const MatchResult(this.item, this.status, {this.statementAmounts = const []});

  final RecordedItem item;
  final MatchStatus status;

  /// Amounts found beside the code, to show when the amount differs.
  final List<double> statementAmounts;
}

final RegExp _codeLike = RegExp(r'[A-Z][A-Z0-9]{9}');
final RegExp _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

/// How far past a code to look for its amount. Statement lines and M-Pesa
/// messages keep the amount close to the code.
const int _lookahead = 220;

final RegExp _dateOrTime = RegExp(
  r'\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}|\d{1,2}:\d{2}(?::\d{2})?',
);

List<double> _numbersIn(String text) {
  final values = <double>[];
  // Dates and times are not amounts.
  final cleanedText = text.replaceAll(_dateOrTime, ' ');
  for (final match in _number.allMatches(cleanedText)) {
    final cleaned = match.group(0)!.replaceAll(',', '');
    final value = double.tryParse(cleaned);
    if (value != null && value.isFinite) values.add(value);
  }
  return values;
}

/// Compares each recorded payment with a pasted statement or pasted messages.
/// Matching is by code, ignoring letter case and spaces. The amount must sit
/// next to the code, before the next code in the text.
List<MatchResult> matchRecorded(
  List<RecordedItem> items,
  String statement,
) {
  final text = statement.toUpperCase();
  return [for (final item in items) _matchOne(item, text)];
}

MatchResult _matchOne(RecordedItem item, String text) {
  final code = item.code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (code.isEmpty || text.trim().isEmpty) {
    return MatchResult(item, MatchStatus.notFound);
  }

  var found = false;
  final seen = <double>[];
  var from = 0;
  while (true) {
    final index = text.indexOf(code, from);
    if (index < 0) break;
    found = true;
    final start = index + code.length;
    var end = start + _lookahead;
    if (end > text.length) end = text.length;
    var segment = text.substring(start, end);
    // Stop at the next code so a neighbour's amount is not used.
    for (final next in _codeLike.allMatches(segment)) {
      if (RegExp(r'\d').hasMatch(next.group(0)!)) {
        segment = segment.substring(0, next.start);
        break;
      }
    }
    final numbers = _numbersIn(segment);
    if (numbers.any((n) => (n - item.amount).abs() < 0.01)) {
      return MatchResult(item, MatchStatus.matched, statementAmounts: numbers);
    }
    seen.addAll(numbers);
    from = start;
  }

  return found
      ? MatchResult(item, MatchStatus.amountDiffers, statementAmounts: seen)
      : MatchResult(item, MatchStatus.notFound);
}

/// Counts for the summary bar.
({int matched, int differs, int missing}) summarise(
    Iterable<MatchResult> results) {
  var matched = 0, differs = 0, missing = 0;
  for (final result in results) {
    switch (result.status) {
      case MatchStatus.matched:
        matched++;
      case MatchStatus.amountDiffers:
        differs++;
      case MatchStatus.notFound:
        missing++;
    }
  }
  return (matched: matched, differs: differs, missing: missing);
}
