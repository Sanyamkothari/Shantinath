import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shantinath_agro/utils/pdf_helper.dart';

/// Renders a sales report to an A4 PDF: summary tiles plus top products,
/// customers, and cities. The caller supplies pre-aggregated rows so the
/// screen's existing aggregation stays the single source of truth.
class SalesReportPdfService {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd MMM yyyy');

  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _grey = PdfColor.fromInt(0xFF666666);

  Future<Uint8List> build({
    required String sellerName,
    required String period,
    required double totalRevenue,
    required int totalUnits,
    required int cityCount,
    required int orderCount,
    required List<List<String>> productRows, // [name, qty, revenue]
    required List<List<String>> customerRows, // [name, village, revenue]
    required List<List<String>> cityRows, // [city, orders, revenue]
  }) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final dev = await PdfGoogleFonts.notoSansDevanagariRegular();
    final theme =
        pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [dev]);

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(sellerName,
                        style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: _green)),
                    pw.Text('Sales Report',
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Period: $period',
                        style: const pw.TextStyle(fontSize: 9, color: _grey)),
                    pw.Text('Generated ${_dateFmt.format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: _grey)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(height: 1),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (ctx) => [
          _summary(totalRevenue, totalUnits, cityCount, orderCount),
          pw.SizedBox(height: 14),
          if (productRows.isNotEmpty) ...[
            _sectionTitle('Top Products'),
            _table(['Product', 'Qty', 'Revenue'], productRows,
                rightCols: {2}),
            pw.SizedBox(height: 14),
          ],
          if (customerRows.isNotEmpty) ...[
            _sectionTitle('Top Customers'),
            _table(['Customer', 'City', 'Revenue'], customerRows,
                rightCols: {2}),
            pw.SizedBox(height: 14),
          ],
          if (cityRows.isNotEmpty) ...[
            _sectionTitle('Top Cities'),
            _table(['City', 'Orders', 'Revenue'], cityRows, rightCols: {2}),
          ],
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _summary(
      double revenue, int units, int cities, int orders) {
    pw.Widget tile(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: const PdfColor.fromInt(0xFFDDDDDD)),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _green)),
                pw.SizedBox(height: 2),
                pw.Text(label,
                    style: const pw.TextStyle(fontSize: 8, color: _grey)),
              ],
            ),
          ),
        );

    return pw.Row(
      children: [
        tile('Total Revenue', _currency.format(revenue)),
        tile('Units Sold', '$units'),
        tile('Orders', '$orders'),
        tile('Cities', '$cities'),
      ],
    );
  }

  pw.Widget _sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _table(List<String> headers, List<List<String>> rows,
      {Set<int> rightCols = const {}}) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border:
          pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _green),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignments: {
        for (final c in rightCols) c: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.5),
      },
    );
  }

  /// Share/print helper.
  Future<void> shareBytes(Uint8List bytes, String filename) {
    return shareOrDownloadPdf(bytes: bytes, filename: filename);
  }
}
