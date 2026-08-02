import 'dart:typed_data';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/utils/ledger_account.dart';

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

  LedgerMovement toMovement() => LedgerMovement(
        date: date,
        voucherType: voucherType,
        voucherNo: voucherNo,
        amount: amount,
        type: type,
        particulars: particulars,
        narration: narration,
      );
}

/// Renders an account statement as the firm's Tally "Ledger Account" print:
/// centred letterhead, party name, period, then a Date / Particulars / Vch Type
/// / Vch No / Debit / Credit table opening with the brought-forward balance and
/// closing with the balancing figure.
class LedgerStatementPdfService {
  static final _money = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('d-MMM-yy');

  static const double _fs = 8.5;

  static pw.TextStyle _s({double size = _fs, bool bold = false}) => pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

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

    // Dr positive. With no known outstanding figure, treat the window as
    // self-contained (opening zero) rather than inventing a balance.
    final closingSigned = outstandingBalance == null
        ? entries.fold<double>(0, (s, e) => s + (e.isDr ? e.amount : -e.amount))
        : (balanceType == 'Cr' ? -outstandingBalance : outstandingBalance);

    final account = LedgerAccount.fromMovements(
      partyName: title,
      movements: entries.map((e) => e.toMovement()).toList(),
      closingSigned: closingSigned,
      from: range?.start,
      to: range?.end,
    );

    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        // Column headings live in the header so they repeat on every page, and
        // the rows table is a TOP-LEVEL child of build() — MultiPage can only
        // split widgets at that level, so wrapping the whole statement in one
        // Column makes a long ledger unsplittable and throws TooManyPages.
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (ctx.pageNumber == 1) _letterhead(account),
            _headings(),
            pw.Divider(height: 3, thickness: 0.5),
          ],
        ),
        build: (ctx) => [
          _rowsTable(account),
          pw.SizedBox(height: 10),
          _closingBlock(account),
        ],
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber}', style: _s(size: 7.5)),
        ),
      ),
    );
    return doc.save();
  }

  // ── letterhead ───────────────────────────────────────────────────────────

  /// The statement letterhead is narrower than the tax invoice's: address,
  /// licences and e-mail only — no GSTIN, state code or phone.
  pw.Widget _letterhead(LedgerAccount a) {
    final lines = <String>[
      AppConstants.sellerAddress,
      if (AppConstants.sellerSeedLicence.isNotEmpty)
        'Seed Licence No.:${AppConstants.sellerSeedLicence}',
      if (AppConstants.sellerSeedLicence2.isNotEmpty)
        'Seed Licence No: ${AppConstants.sellerSeedLicence2}',
      if (AppConstants.sellerFertilizerWholesaleLicence.isNotEmpty)
        'Fertilizer Wholesale Lic No : '
            '${AppConstants.sellerFertilizerWholesaleLicence}',
      if (AppConstants.sellerFertilizerRetailLicence.isNotEmpty)
        'Fertilizer Retail Lic. NO.: '
            '${AppConstants.sellerFertilizerRetailLicence}',
      if (AppConstants.sellerEmail.isNotEmpty)
        'E-Mail : ${AppConstants.sellerEmail}',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(AppConstants.sellerName,
            style: _s(size: 11, bold: true),
            textAlign: pw.TextAlign.center),
        for (final l in lines)
          pw.Text(l,
              style: _s(size: 8),
              textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 8),
        pw.Text(a.partyName,
            style: _s(size: 11, bold: true),
            textAlign: pw.TextAlign.center),
        pw.Text('Ledger Account',
            style: _s(size: 8.5),
            textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 10),
        pw.Text('${_dateFmt.format(a.from)} to ${_dateFmt.format(a.to)}',
            style: _s(size: 8.5),
            textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 8),
      ],
    );
  }

  // ── table ────────────────────────────────────────────────────────────────

  static const _cols = <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(52),  // Date
    1: pw.FixedColumnWidth(16),  // To / By
    2: pw.FlexColumnWidth(3.4),  // Particulars
    3: pw.FixedColumnWidth(62),  // Vch Type
    4: pw.FixedColumnWidth(48),  // Vch No.
    5: pw.FixedColumnWidth(74),  // Debit
    6: pw.FixedColumnWidth(74),  // Credit
  };

  pw.Widget _c(String t,
          {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
        child: pw.Text(t, style: _s(bold: bold), textAlign: align),
      );

  pw.Widget _headings() => pw.Table(
        columnWidths: _cols,
        children: [
          pw.TableRow(children: [
            _c('Date', bold: true, align: pw.TextAlign.center),
            _c(''),
            _c('Particulars', bold: true, align: pw.TextAlign.center),
            _c('Vch Type', bold: true, align: pw.TextAlign.center),
            _c('Vch No.', bold: true, align: pw.TextAlign.center),
            _c('Debit', bold: true, align: pw.TextAlign.right),
            _c('Credit', bold: true, align: pw.TextAlign.right),
          ]),
        ],
      );

  pw.Widget _rowsTable(LedgerAccount a) {
    String money(double? v) => v == null ? '' : _money.format(v);

    return pw.Table(
      columnWidths: _cols,
      children: [
        for (final r in a.rows)
          pw.TableRow(children: [
            _c(r.date == null ? '' : _dateFmt.format(r.date!),
                align: pw.TextAlign.right),
            _c(r.prefix),
            _c(r.particulars, bold: true),
            _c(r.voucherType),
            _c(r.voucherNo, align: pw.TextAlign.right),
            _c(money(r.debit), align: pw.TextAlign.right),
            _c(money(r.credit), align: pw.TextAlign.right),
          ]),
      ],
    );
  }

  /// Column totals, the balancing closing figure, and the grand total that both
  /// columns foot to.
  pw.Widget _closingBlock(LedgerAccount a) => pw.Table(
        columnWidths: _cols,
        children: [
          pw.TableRow(children: [
            _c(''),
            _c(''),
            _c(''),
            _c(''),
            _c(''),
            _c(_money.format(a.debitTotal), align: pw.TextAlign.right),
            _c(_money.format(a.creditTotal), align: pw.TextAlign.right),
          ]),
          pw.TableRow(children: [
            _c(''),
            _c(a.closingPrefix),
            _c('Closing Balance', bold: true),
            _c(''),
            _c(''),
            _c(a.closesOnDebit ? _money.format(a.closingFigure) : '',
                align: pw.TextAlign.right),
            _c(a.closesOnDebit ? '' : _money.format(a.closingFigure),
                align: pw.TextAlign.right),
          ]),
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 0.5),
                bottom: pw.BorderSide(width: 0.5),
              ),
            ),
            children: [
              _c(''),
              _c(''),
              _c(''),
              _c(''),
              _c(''),
              _c(_money.format(a.grandTotal),
                  bold: true, align: pw.TextAlign.right),
              _c(_money.format(a.grandTotal),
                  bold: true, align: pw.TextAlign.right),
            ],
          ),
        ],
      );
}
