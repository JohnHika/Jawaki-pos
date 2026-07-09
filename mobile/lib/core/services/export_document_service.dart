import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// A single labeled block of tabular data in a generated PDF report — one
/// section per table (e.g. "Sales", "Inventory"), so the same builder can
/// render a dashboard summary, a receipt, or a settings data export without
/// three bespoke layouts.
class PdfReportSection {
  final String heading;
  final List<String> headers;
  final List<List<String>> rows;

  const PdfReportSection({
    required this.heading,
    required this.headers,
    required this.rows,
  });
}

/// Shared document generation for every share/export site in the app
/// (dashboard report, receipt, settings data exports) — one flexible PDF
/// builder and one CSV builder reused everywhere instead of copy-pasted
/// per-export logic.
class ExportDocumentService {
  static const _accent = PdfColor.fromInt(0xFFFF7A33);
  static const _ink = PdfColor.fromInt(0xFF0B0A0F);
  static const _muted = PdfColor.fromInt(0xFF6B7280);

  /// Builds a branded PDF: company name/logo header, an accent rule, then
  /// one or more tabular sections. Returns the PDF bytes ready to save or
  /// share — callers decide what to do with them (this service never
  /// touches the share sheet itself, matching how sharePlainText/CSV work).
  static Future<Uint8List> buildPdfReport({
    required String title,
    required String companyName,
    String? subtitle,
    Uint8List? logoBytes,
    List<PdfReportSection> sections = const [],
    String? bodyText,
  }) async {
    final doc = pw.Document();
    final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      title,
                      style: pw.TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
                if (logoImage != null)
                  pw.ClipRRect(
                    horizontalRadius: 8,
                    verticalRadius: 8,
                    child: pw.Image(logoImage, width: 44, height: 44, fit: pw.BoxFit.cover),
                  ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(height: 2.5, color: _accent),
            pw.SizedBox(height: 16),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}  •  Generated from Axon POS',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        build: (context) => [
          if (subtitle != null) ...[
            pw.Text(
              subtitle,
              style: pw.TextStyle(fontSize: 11, color: _muted),
            ),
            pw.SizedBox(height: 14),
          ],
          if (bodyText != null) ...[
            pw.Text(
              bodyText,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
            pw.SizedBox(height: 18),
          ],
          for (final section in sections) ...[
            pw.Text(
              section.heading,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F4F6)),
                  children: [
                    for (final header in section.headers)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                        child: pw.Text(
                          header,
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                for (final row in section.rows)
                  pw.TableRow(
                    children: [
                      for (final cell in row)
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                          child: pw.Text(cell, style: const pw.TextStyle(fontSize: 9)),
                        ),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 18),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Saves PDF bytes to a shareable file and opens the OS share sheet —
  /// mirrors the existing Share.shareXFiles pattern used for CSV exports.
  static Future<void> sharePdf(Uint8List bytes, String filenamePrefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/${filenamePrefix}_$timestamp.pdf');
    await file.writeAsBytes(bytes);
    await Printing.sharePdf(bytes: bytes, filename: file.path.split(Platform.pathSeparator).last);
  }

  /// Fetches a network logo image as bytes for embedding in a PDF header;
  /// returns null on any failure so callers can render without a logo
  /// instead of failing the whole export.
  static Future<Uint8List?> fetchLogoBytes(String? logoUrl) async {
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty) return null;
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  static String buildCsv(List<String> headers, List<List<String>> rows) {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvEscape).join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_csvEscape).join(','));
    }
    return buffer.toString();
  }

  static Future<void> shareCsv(String content, String filenamePrefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/${filenamePrefix}_$timestamp.csv');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: 'Axon POS export');
  }

  static Future<void> sharePlainText(String content, {String? subject}) {
    return Share.share(content, subject: subject);
  }

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
