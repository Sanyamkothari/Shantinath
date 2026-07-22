import 'dart:typed_data';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// A normalized statement line, independent of the Firestore shape each screen
/// uses, so both the admin Ledger Book and the customer ledger can share one
/// PDF builder.
class LedgerStatementEntry {
  final DateTime date;
  final String voucherType;
  final String voucherNo;
  final double amount;
  final String type; // 'Dr' | 'Cr'
  final String particulars;
  final String narration;

  /// Signed running balance at this row (Dr positive, Cr negative). Optional.
  final double? runningBalanceSigned;

  const LedgerStatementEntry({
    required this.date,
    required this.voucherType,
    required this.voucherNo,
    required this.amount,
    required this.type,
    this.particulars = '',
    this.narration = '',
    this.runningBalanceSigned,
  });

  bool get isDr => type != 'Cr';
}

/// Renders an account statement to an A4 PDF, shared by all ledger screens.
class LedgerStatementPdfService {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd MMM yyyy');

  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _grey = PdfColor.fromInt(0xFF666666);

  Future<Uint8List> build({
    required String title,
    double? outstandingBalance,
    String balanceType = 'Dr',
    required List<LedgerStatementEntry> entries,
    DateTimeRange? range,
  }) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final dev = await PdfGoogleFonts.notoSansDevanagariRegular();
    final theme =
        pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [dev]);

    double debit = 0, credit = 0;
    for (final e in entries) {
      if (e.isDr) {
        debit += e.amount;
      } else {
        credit += e.amount;
      }
    }
    final showBalance = entries.any((e) => e.runningBalanceSigned != null);

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text(
              'Account Statement   ·   Generated ${_dateFmt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: _grey),
            ),
            if (range != null)
              pw.Text(
                'Period: ${_dateFmt.format(range.start)} – ${_dateFmt.format(range.end)}',
                style: const pw.TextStyle(fontSize: 9, color: _grey),
              ),
            if (outstandingBalance != null)
              pw.Text(
                'Outstanding: ${_currency.format(outstandingBalance)} $balanceType',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            pw.SizedBox(height: 6),
            pw.Divider(height: 1),
          ],
        ),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Type',
              'Voucher',
              'Particulars',
              'Amount',
              'Dr/Cr',
              if (showBalance) 'Balance',
            ],
            data: entries
                .map((e) => [
                      _dateFmt.format(e.date),
                      e.voucherType,
                      e.voucherNo,
                      e.narration.isNotEmpty ? e.narration : e.particulars,
                      _currency.format(e.amount),
                      e.isDr ? 'Dr' : 'Cr',
                      if (showBalance)
                        e.runningBalanceSigned == null
                            ? ''
                            : '${_currency.format(e.runningBalanceSigned!.abs())} ${e.runningBalanceSigned! < 0 ? 'Cr' : 'Dr'}',
                    ])
                .toList(),
            border:
                pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCCCCCC), width: 0.5),
            headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: _green),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignments: {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.center,
              6: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(2.4),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(0.7),
              if (showBalance) 6: const pw.FlexColumnWidth(1.4),
            },
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total Debit: ${_currency.format(debit)}     ',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Total Credit: ${_currency.format(credit)}',
                  style:
                      pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }
}
