import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/utils/amount_in_words.dart';

/// One line of the invoice goods table.
class InvoiceLine {
  final String description;
  final String batch;
  final String hsn;
  final double qty;
  final String unit;
  final double rate;
  final double amount;

  const InvoiceLine({
    required this.description,
    required this.qty,
    required this.amount,
    this.batch = '',
    this.hsn = '',
    this.unit = '',
    this.rate = 0,
  });
}

/// Renders a sales bill as an A4 TAX INVOICE laid out like the firm's Tally
/// print: bordered goods table, HSN summary, amount in words, declaration and
/// authorised-signatory block.
///
/// Fields the Tally sync does not yet provide (HSN, batch, buyer state) render
/// as empty cells rather than shifting the layout, so the document stays
/// recognisable while that data is being backfilled.
class InvoicePdfService {
  static final _money = NumberFormat('#,##,##0.00', 'en_IN');
  static final _qtyFmt = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('d-MMM-yy');

  static const PdfColor _line = PdfColor.fromInt(0xFF000000);
  static const double _fs = 8.0;

  /// Approximate height of one goods row, and of the table body on a Tally
  /// print. Used only to pad short bills so they keep the familiar tall box.
  static const double _rowHeight = 16;
  static const double _bodyHeight = 330;

  static pw.TextStyle _s({double size = _fs, bool bold = false}) => pw.TextStyle(
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  Future<Uint8List> build({
    required String partyName,
    required String invoiceNo,
    required DateTime date,
    required List<InvoiceLine> items,
    required double total,
    String refNo = '',
    String partyState = AppConstants.sellerStateName,
    String partyStateCode = AppConstants.sellerStateCode,
    String partyGstNo = '',
    String partyAddress = '',
  }) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final dev = await PdfGoogleFonts.notoSansDevanagariRegular();
    final theme =
        pw.ThemeData.withFont(base: base, bold: bold, fontFallback: [dev]);

    final doc = pw.Document(theme: theme);
    // MultiPage, not Page. A fixed Page silently CLIPS an over-long goods table
    // — it still prints a correct grand total, so the invoice looks internally
    // consistent while quietly omitting line items. On a tax invoice that is the
    // worst possible failure, so long bills paginate instead.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        build: (ctx) => [
          _topBar(invoiceNo, refNo, date),
          pw.SizedBox(height: 10),
          _sellerBlock(),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('TAX INVOICE', style: _s(size: 11, bold: true)),
          ),
          pw.SizedBox(height: 6),
          _partyBlock(
              partyName, partyAddress, partyState, partyStateCode, partyGstNo),
          pw.SizedBox(height: 4),
          _goodsTable(items, total),
          _amountInWordsBlock(total),
          pw.SizedBox(height: 6),
          _hsnSummary(items, total),
          pw.SizedBox(height: 8),
          _footer(),
        ],
      ),
    );
    return doc.save();
  }

  // ── header ───────────────────────────────────────────────────────────────

  pw.Widget _topBar(String invoiceNo, String refNo, DateTime date) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Invoice No.   $invoiceNo', style: _s()),
                if (refNo.isNotEmpty)
                  pw.Text('Ref. No.   $refNo', style: _s()),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(
                'SUBJECT TO ${AppConstants.sellerJurisdiction} JURISDICTION',
                style: _s().copyWith(decoration: pw.TextDecoration.underline),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Dated  ${_dateFmt.format(date)}', style: _s()),
            ),
          ),
        ],
      );

  pw.Widget _sellerBlock() {
    final lines = <String>[
      AppConstants.sellerAddress,
      if (AppConstants.sellerSeedLicence.isNotEmpty)
        'Seed Licence No:${AppConstants.sellerSeedLicence}',
      if (AppConstants.sellerSeedLicence2.isNotEmpty)
        'Seed Licence No: ${AppConstants.sellerSeedLicence2}',
      if (AppConstants.sellerFertilizerWholesaleLicence.isNotEmpty)
        'Fertilizer Wholesale Lic No : '
            '${AppConstants.sellerFertilizerWholesaleLicence}',
      if (AppConstants.sellerFertilizerRetailLicence.isNotEmpty)
        'Fertilizer Retail Lic. NO.: '
            '${AppConstants.sellerFertilizerRetailLicence}',
      if (AppConstants.sellerPesticideLicence.isNotEmpty)
        'Pesticide Lic. No.: ${AppConstants.sellerPesticideLicence}',
      if (AppConstants.sellerGstNo.isNotEmpty)
        'GSTIN/UIN: ${AppConstants.sellerGstNo}',
      'State Name : ${AppConstants.sellerStateName}, Code : '
          '${AppConstants.sellerStateCode}',
      if (AppConstants.sellerPhone.isNotEmpty)
        'Contact : ${AppConstants.sellerPhone}',
      if (AppConstants.sellerEmail.isNotEmpty)
        'E-Mail : ${AppConstants.sellerEmail}',
    ];

    return pw.Column(
      children: [
        pw.Text(AppConstants.sellerName, style: _s(size: 9.5, bold: true)),
        for (final l in lines)
          pw.Text(l, style: _s(size: 7.5), textAlign: pw.TextAlign.center),
      ],
    );
  }

  pw.Widget _partyBlock(String name, String address, String state,
          String stateCode, String gstNo) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text('Party :  $name', style: _s(size: 9, bold: true)),
          ),
          if (address.isNotEmpty)
            pw.Center(child: pw.Text(address, style: _s(size: 7.5))),
          pw.SizedBox(height: 2),
          if (gstNo.isNotEmpty)
            pw.Text('           GSTIN/UIN        : $gstNo', style: _s()),
          pw.Text('           State Name      : $state, Code : $stateCode',
              style: _s()),
          pw.Text('           Place of Supply : $state', style: _s()),
        ],
      );

  // ── goods table ──────────────────────────────────────────────────────────

  static const _cols = <int, pw.TableColumnWidth>{
    0: pw.FixedColumnWidth(22),   // Sl No.
    1: pw.FlexColumnWidth(4.2),   // Description of Goods
    2: pw.FixedColumnWidth(42),   // HSN/SAC
    3: pw.FixedColumnWidth(58),   // Quantity
    4: pw.FixedColumnWidth(44),   // Rate
    5: pw.FixedColumnWidth(30),   // per
    6: pw.FixedColumnWidth(64),   // Amount
  };

  pw.Widget _cell(String text,
          {bool bold = false,
          pw.TextAlign align = pw.TextAlign.left,
          double pad = 3}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: pad, vertical: 2),
        child: pw.Text(text, style: _s(bold: bold), textAlign: align),
      );

  pw.Widget _goodsTable(List<InvoiceLine> items, double total) {
    final totalQty = items.fold<double>(0, (s, i) => s + i.qty);
    // Tally prints the unit once on the totals row; only meaningful when every
    // line shares a unit, so fall back to blank on mixed-unit bills.
    final units = items.map((i) => i.unit).where((u) => u.isNotEmpty).toSet();
    final totalUnit = units.length == 1 ? units.first : '';

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: _cols,
      children: [
        pw.TableRow(children: [
          _cell('Sl\nNo.', bold: true, align: pw.TextAlign.center),
          _cell('Description of Goods', bold: true, align: pw.TextAlign.center),
          _cell('HSN/SAC', bold: true, align: pw.TextAlign.center),
          _cell('Quantity', bold: true, align: pw.TextAlign.center),
          _cell('Rate', bold: true, align: pw.TextAlign.center),
          _cell('per', bold: true, align: pw.TextAlign.center),
          _cell('Amount', bold: true, align: pw.TextAlign.center),
        ]),
        for (var i = 0; i < items.length; i++) _goodsRow(i + 1, items[i]),
        // Blank filler so a short bill still shows the tall boxed body of the
        // Tally print. Sized from the rows already used, and clamped at zero so
        // a long bill doesn't get pushed onto an extra page for cosmetics.
        pw.TableRow(children: [
          for (var c = 0; c < 7; c++)
            pw.SizedBox(
                height: (_bodyHeight - items.length * _rowHeight)
                    .clamp(0, _bodyHeight)
                    .toDouble()),
        ]),
        pw.TableRow(children: [
          _cell(''),
          _cell('Total', bold: true, align: pw.TextAlign.right),
          _cell(''),
          _cell(
              totalQty == 0
                  ? ''
                  : '${_qtyFmt.format(totalQty)}${totalUnit.isEmpty ? '' : ' $totalUnit'}',
              bold: true,
              align: pw.TextAlign.center),
          _cell(''),
          _cell(''),
          _cell('₹ ${_money.format(total)}',
              bold: true, align: pw.TextAlign.right),
        ]),
      ],
    );
  }

  pw.TableRow _goodsRow(int sl, InvoiceLine it) => pw.TableRow(children: [
        _cell('$sl', align: pw.TextAlign.center),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(it.description, style: _s(bold: true)),
              if (it.batch.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 10),
                  child: pw.Text('Batch:  ${it.batch}',
                      style: _s(size: 7).copyWith(
                          fontStyle: pw.FontStyle.italic)),
                ),
            ],
          ),
        ),
        _cell(it.hsn, align: pw.TextAlign.center),
        _cell(
            '${_qtyFmt.format(it.qty)}${it.unit.isEmpty ? '' : ' ${it.unit}'}',
            align: pw.TextAlign.center),
        _cell(it.rate == 0 ? '' : _money.format(it.rate),
            align: pw.TextAlign.right),
        _cell(it.unit, align: pw.TextAlign.center),
        _cell(_money.format(it.amount), align: pw.TextAlign.right),
      ]);

  // ── totals / summary ─────────────────────────────────────────────────────

  pw.Widget _amountInWordsBlock(double total) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.SizedBox(height: 3),
          pw.Text('Amount Chargeable (in words)', style: _s(size: 7)),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Text(amountInWords(total), style: _s(bold: true)),
              ),
              pw.Text('E. & O.E.', style: _s(size: 7)),
            ],
          ),
        ],
      );

  /// HSN-wise taxable value. Lines with no HSN are grouped under a blank key so
  /// the total still reconciles with the invoice total.
  pw.Widget _hsnSummary(List<InvoiceLine> items, double total) {
    final byHsn = <String, double>{};
    for (final i in items) {
      byHsn[i.hsn] = (byHsn[i.hsn] ?? 0) + i.amount;
    }
    final rows = byHsn.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    pw.Widget c(String t, {bool bold = false, bool right = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Text(t,
              style: _s(bold: bold),
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
        );

    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(5),
        1: pw.FixedColumnWidth(90),
      },
      children: [
        pw.TableRow(children: [
          c('HSN/SAC', bold: true),
          c('Taxable\nValue', bold: true, right: true),
        ]),
        for (final e in rows)
          pw.TableRow(children: [
            c(e.key),
            c(_money.format(e.value), right: true),
          ]),
        pw.TableRow(children: [
          c('Total', bold: true, right: true),
          c(_money.format(total), bold: true, right: true),
        ]),
      ],
    );
  }

  // ── footer ───────────────────────────────────────────────────────────────

  pw.Widget _footer() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('Tax Amount (in words) :  NIL', style: _s()),
          if (AppConstants.sellerPan.isNotEmpty)
            pw.Text("Company's PAN            :  ${AppConstants.sellerPan}",
                style: _s()),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Declaration',
                        style: _s(size: 7.5).copyWith(
                            decoration: pw.TextDecoration.underline)),
                    pw.Text(
                      'We declare that this invoice shows the actual price of the '
                      'goods described and that all particulars are true and correct. '
                      'Payment of this bill should be made within '
                      '${AppConstants.invoicePaymentDays} days in case of failure '
                      'interest @ ${AppConstants.invoiceOverdueInterestPct.toStringAsFixed(0)}% '
                      'will be charged.',
                      style: _s(size: 7.5),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 2,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('for ${AppConstants.sellerName}',
                        style: _s(size: 7.5, bold: true),
                        textAlign: pw.TextAlign.center),
                    pw.SizedBox(height: 34),
                    pw.Text('Authorised Signatory', style: _s(size: 7.5)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('This is a Computer Generated Invoice',
                style: _s(size: 7.5).copyWith(
                    decoration: pw.TextDecoration.underline)),
          ),
        ],
      );
}
