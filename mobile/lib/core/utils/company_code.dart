import 'package:flutter/services.dart';

/// Company codes are lowercase words joined by hyphens, like
/// `levisa-ventures`.
class CompanyCode {
  const CompanyCode._();

  static final _pattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// The code as it is sent and stored: no spaces, no leading or trailing
  /// hyphens.
  static String normalize(String value) {
    final typed = CompanyCodeFormatter.clean(value);
    return typed.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static bool isValid(String value) => _pattern.hasMatch(value);
}

/// Turns a typed space into a hyphen as the person types, so the field
/// never shows a space. Capitals become lowercase and other symbols are
/// dropped. A trailing hyphen stays while typing so the next word can follow.
class CompanyCodeFormatter extends TextInputFormatter {
  const CompanyCodeFormatter();

  static String clean(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9-]'), '')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceFirst(RegExp(r'^-+'), '');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = clean(newValue.text);
    if (text == newValue.text) return newValue;
    final caret = newValue.selection.isValid
        ? clean(newValue.text
                .substring(0, newValue.selection.extentOffset.clamp(0, newValue.text.length)))
            .length
        : text.length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
  }
}
