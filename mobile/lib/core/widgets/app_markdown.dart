import 'package:flutter/material.dart';
import 'package:gpt_markdown_lite/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown_lite/gpt_markdown_lite.dart';

/// Markdown renderer used for AI replies, daily briefs and summaries.
///
/// `GptMarkdown` draws tables as one wide sideways-scrolling grid, which on a
/// phone clips every column after the first and hides most of the advice (the
/// "Reason" and "Expected result" columns of a recommendation table). This
/// wrapper swaps the table component for [StackedTableMd], which shows each row
/// as a small card with labelled fields that wrap to the screen width.
class AppMarkdown extends StatelessWidget {
  const AppMarkdown(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  static final List<MarkdownComponent> _components = [
    CodeBlockMd(),
    NewLines(),
    BlockQuote(),
    ImageMd(),
    ATagMd(),
    StackedTableMd(),
    HTag(),
    UnOrderedList(),
    OrderedList(),
    RadioButtonMd(),
    CheckBoxMd(),
    HrLine(),
    StrikeMd(),
    BoldMd(),
    ItalicMd(),
    HighlightedText(),
    SourceTag(),
    IndentMd(),
  ];

  @override
  Widget build(BuildContext context) =>
      GptMarkdown(data, style: style, components: _components);
}

/// Parsed form of a markdown table, kept separate so it can be unit tested.
class ParsedTable {
  const ParsedTable({required this.header, required this.rows});

  /// Column titles, or empty when the table had no header row.
  final List<String> header;
  final List<List<String>> rows;
}

/// Splits a markdown table into header + body rows. Returns null when the text
/// holds no data rows. Alignment/separator rows (`|---|:--:|`) are dropped.
ParsedTable? parseMarkdownTable(String text) {
  bool isSeparator(List<String> row) =>
      row.isNotEmpty &&
      row.every((c) => c.isEmpty || RegExp(r'^:?-{2,}:?$').hasMatch(c));

  final rows = text
      .trim()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.startsWith('|'))
      .map((line) => line
          .replaceFirst(RegExp(r'^\|'), '')
          .replaceFirst(RegExp(r'\|$'), '')
          .split('|')
          .map((cell) => cell.trim())
          .toList())
      .toList();
  if (rows.isEmpty) return null;

  final hasHeader = rows.length >= 2 && isSeparator(rows[1]);
  final body = rows.where((row) => !isSeparator(row)).toList();
  final header = hasHeader ? body.removeAt(0) : <String>[];
  final dataRows = body.where((row) => row.any((c) => c.isNotEmpty)).toList();
  if (dataRows.isEmpty) return null;
  return ParsedTable(header: header, rows: dataRows);
}

/// Renders a markdown table as a stack of cards: the first column is the card
/// title, every other column becomes a labelled line underneath.
class StackedTableMd extends BlockMd {
  @override
  String get expString => TableMd().expString;

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final table = parseMarkdownTable(text);
    if (table == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final base = config.style ?? Theme.of(context).textTheme.bodyMedium;
    final labelStyle = base?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: scheme.onSurface.withValues(alpha: 0.6),
    );

    Widget cell(String value, {TextStyle? style}) => MdWidget(
          value,
          false,
          config: style == null ? config : config.copyWith(style: style),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in table.rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (row.first.isNotEmpty)
                    cell(row.first,
                        style: base?.copyWith(fontWeight: FontWeight.w700)),
                  for (var i = 1; i < row.length; i++)
                    if (row[i].isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (i < table.header.length &&
                          table.header[i].isNotEmpty)
                        Text(table.header[i].toUpperCase(), style: labelStyle),
                      cell(row[i]),
                    ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
