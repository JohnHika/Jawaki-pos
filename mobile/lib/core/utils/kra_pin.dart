/// A KRA PIN is a letter, nine digits and a letter, for example A123456789B.
class KraPin {
  KraPin._();

  static final _shape = RegExp(r'^[A-Z]\d{9}[A-Z]$');

  /// Upper case with spaces removed, the way it is stored and printed.
  static String normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  static bool isValid(String value) => _shape.hasMatch(normalize(value));

  /// The PIN to print on a receipt: only when the owner has saved one and
  /// switched printing on. Anything else prints nothing.
  static String? forReceipt(Map<String, dynamic>? user) {
    final tenant = user?['tenant'];
    final settings = tenant is Map ? tenant['settings'] : null;
    if (settings is! Map) return null;
    if (settings['showKraPinOnReceipts'] != true) return null;
    final pin = normalize(settings['kraPin']?.toString() ?? '');
    return isValid(pin) ? pin : null;
  }
}
