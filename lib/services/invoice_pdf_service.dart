import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Renders a single sales invoice (bill) to an A4 PDF from the line items and
/// ledger breakup synced out of Tally. Shared by the admin "Bills" tab so a bill
/// can be viewed and shared/sent to the shop.
class InvoicePdfService {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _qty = NumberFormat('#,##0.##', 'en_IN');
  static final _dateFmt = DateFormat('dd MMM yyyy');

  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _grey = PdfColor.fromInt(0xFF666666);

  Future<Uint8List> build({
    required String sellerName,
    required String sellerAddress,
    required String partyName,
    String partyVillage = '',
    String partyPhone = '',
    required String invoiceNo,
    required String voucherType,
    required DateTime date,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> ledgers,
    required double taxableValue,
    required double total,
  }) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final dev = await PdfGoogleFonts.notoSansDevanagariRegular();
    final theme =
        pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [dev]);

    // Split the credit ledgers into the main goods/sales ledger (closest to the
    // taxable value) and any extra charges/taxes (hamali, CGST/SGST, …).
    final crs = ledgers.where((l) => (l['type'] as String?) == 'Cr').toList();
    Map<String, dynamic>? sales;
    double bestDiff = double.infinity;
    for (final l in crs) {
      final amt = (l['amount'] as num?)?.toDouble() ?? 0;
      final d = (amt - taxableValue).abs();
      if (d < bestDiff) {
        bestDiff = d;
        sales = l;
      }
    }
    final charges = crs.where((l) => !identical(l, sales)).toList();

    double n(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(sellerName,
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: _green)),
                  if (sellerAddress.isNotEmpty)
                    pw.Text(sellerAddress,
                        style: const pw.TextStyle(fontSize: 9, color: _grey)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text('$voucherType  ·  #$invoiceNo',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(_dateFmt.format(date),
                      style: const pw.TextStyle(fontSize: 9, color: _grey)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(height: 1),
          pw.SizedBox(height: 8),
          pw.Text('Bill To',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
          pw.Text(partyName,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if ([partyVillage, partyPhone].any((s) => s.isNotEmpty))
            pw.Text(
              [partyVillage, partyPhone].where((s) => s.isNotEmpty).join('  •  '),
              style: const pw.TextStyle(fontSize: 9, color: _grey),
            ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Item', 'Qty', 'Rate', 'Amount'],
            data: [
              for (int i = 0; i < items.length; i++)
                [
                  '${i + 1}',
                  (items[i]['item'] ?? '').toString(),
                  '${_qty.format(n(items[i]['qty']))} ${items[i]['unit'] ?? ''}'
                      .trim(),
                  _currency.format(n(items[i]['rate'])),
                  _currency.format(n(items[i]['amount'])),
                ],
            ],
            border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
            headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _green),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              0: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(3.2),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.6),
            },
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(children: [
                _totalRow('Taxable value', _currency.format(taxableValue)),
                for (final c in charges)
                  _totalRow((c['ledger'] ?? 'Charge').toString(),
                      _currency.format(n(c['amount']))),
                pw.Divider(height: 6),
                _totalRow('Grand Total', _currency.format(total), bold: true),
              ]),
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Generated from Tally data · ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: _grey),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
        fontSize: bold ? 12 : 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(value, style: style),
        ],
      ),
    );
  }
}
