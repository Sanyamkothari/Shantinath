import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shantinath_agro/models/delivery_memo.dart';

/// Renders a [DeliveryMemo] to an A4 PDF suitable for printing or sharing.
///
/// Devanagari (Marathi) glyphs are supported by embedding Noto Sans Devanagari
/// as a font fallback — fetched and cached by the `printing` package, so no
/// TTF needs to be bundled as an asset.
class DeliveryMemoPdfService {
  static final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final _dateFmt = DateFormat('dd-MM-yyyy');

  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _grey = PdfColor.fromInt(0xFF666666);
  static const PdfColor _line = PdfColor.fromInt(0xFFBBBBBB);

  /// Builds the memo PDF and returns its bytes.
  Future<Uint8List> buildPdf(DeliveryMemo memo) async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final dev = await PdfGoogleFonts.notoSansDevanagariRegular();
    final devBold = await PdfGoogleFonts.notoSansDevanagariBold();

    final theme = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [dev, devBold],
    );

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _header(memo),
            pw.SizedBox(height: 10),
            _partyBlock(memo),
            pw.SizedBox(height: 10),
            _itemsTable(memo),
            pw.SizedBox(height: 6),
            _totals(memo),
            if (memo.vehicleNo.isNotEmpty ||
                memo.transporter.isNotEmpty ||
                memo.notes.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _transportAndNotes(memo),
            ],
            pw.Spacer(),
            _signatures(memo),
            if (memo.cancelled) _cancelledNote(memo),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _header(DeliveryMemo memo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    memo.sellerName,
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: _green),
                  ),
                  if (memo.sellerAddress.isNotEmpty)
                    pw.Text(memo.sellerAddress,
                        style: const pw.TextStyle(fontSize: 9, color: _grey)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _joinNonEmpty([
                      if (memo.sellerPhone.isNotEmpty)
                        'Ph: ${memo.sellerPhone}',
                      if (memo.sellerGst.isNotEmpty)
                        'GSTIN: ${memo.sellerGst}',
                    ]),
                    style: const pw.TextStyle(fontSize: 9, color: _grey),
                  ),
                  pw.Text(
                    _joinNonEmpty([
                      if (memo.sellerSeedLicence.isNotEmpty)
                        'Seed Lic: ${memo.sellerSeedLicence}',
                      if (memo.sellerFertLicence.isNotEmpty)
                        'Fert Lic: ${memo.sellerFertLicence}',
                      if (memo.sellerPesticideLicence.isNotEmpty)
                        'Pest Lic: ${memo.sellerPesticideLicence}',
                    ]),
                    style: const pw.TextStyle(fontSize: 9, color: _grey),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('DELIVERY MEMO',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('वितरण मेमो',
                    style: const pw.TextStyle(fontSize: 9, color: _grey)),
                pw.SizedBox(height: 4),
                pw.Text('No: ${memo.memoNumber}',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('Date: ${_dateFmt.format(memo.createdAt)}',
                    style: const pw.TextStyle(fontSize: 10)),
                if (memo.cancelled)
                  pw.Text('** CANCELLED **',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFFC62828))),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: _line, height: 1),
      ],
    );
  }

  pw.Widget _partyBlock(DeliveryMemo memo) {
    final partyName =
        memo.customerFirm.isNotEmpty ? memo.customerFirm : memo.customerName;
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('To (Party):',
              style: const pw.TextStyle(fontSize: 8, color: _grey)),
          pw.Text(partyName,
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text(
            _joinNonEmpty([
              if (memo.customerName.isNotEmpty &&
                  memo.customerFirm.isNotEmpty)
                memo.customerName,
              if (memo.customerVillage.isNotEmpty) memo.customerVillage,
              if (memo.customerPhone.isNotEmpty) 'Ph: ${memo.customerPhone}',
            ]),
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            _joinNonEmpty([
              if (memo.customerGst.isNotEmpty) 'GSTIN: ${memo.customerGst}',
              if (memo.customerSeedLicence.isNotEmpty)
                'Seed Lic: ${memo.customerSeedLicence}',
              if (memo.customerFertLicence.isNotEmpty)
                'Fert Lic: ${memo.customerFertLicence}',
            ]),
            style: const pw.TextStyle(fontSize: 9, color: _grey),
          ),
        ],
      ),
    );
  }

  pw.Widget _itemsTable(DeliveryMemo memo) {
    final showPrices = memo.showPrices;

    final headers = <String>[
      '#',
      'Product',
      'Pack',
      'Batch/Lot',
      'Qty',
      if (showPrices) 'Rate',
      if (showPrices) 'Amount',
    ];

    final rows = <List<String>>[];
    for (var i = 0; i < memo.lines.length; i++) {
      final l = memo.lines[i];
      rows.add([
        '${i + 1}',
        l.productName,
        l.packSize,
        l.batchLot,
        '${l.quantity}',
        if (showPrices) _currency.format(l.rate),
        if (showPrices) _currency.format(l.amount),
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(color: _line, width: 0.5),
      headerStyle: pw.TextStyle(
          fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: _green),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellHeight: 22,
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FixedColumnWidth(40),
        if (showPrices) 5: const pw.FlexColumnWidth(1.2),
        if (showPrices) 6: const pw.FlexColumnWidth(1.4),
      },
    );
  }

  pw.Widget _totals(DeliveryMemo memo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text('Total Qty: ${memo.totalQuantity}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        if (memo.showPrices) ...[
          pw.SizedBox(width: 20),
          pw.Text('Total: ${_currency.format(memo.totalAmount)}',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ],
    );
  }

  pw.Widget _transportAndNotes(DeliveryMemo memo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (memo.vehicleNo.isNotEmpty || memo.transporter.isNotEmpty)
          pw.Text(
            _joinNonEmpty([
              if (memo.vehicleNo.isNotEmpty) 'Vehicle: ${memo.vehicleNo}',
              if (memo.transporter.isNotEmpty)
                'Transporter: ${memo.transporter}',
              if (memo.driverName.isNotEmpty) 'Driver: ${memo.driverName}',
            ]),
            style: const pw.TextStyle(fontSize: 9),
          ),
        if (memo.notes.isNotEmpty)
          pw.Text('Notes: ${memo.notes}',
              style: const pw.TextStyle(fontSize: 9, color: _grey)),
      ],
    );
  }

  pw.Widget _signatures(DeliveryMemo memo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'Received the above goods in good condition.',
          style: const pw.TextStyle(fontSize: 9, color: _grey),
        ),
        pw.SizedBox(height: 24),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Receiver\'s Signature',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('For ${memo.sellerName}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ],
    );
  }

  pw.Widget _cancelledNote(DeliveryMemo memo) {
    final by =
        memo.cancelledByName.isNotEmpty ? ' by ${memo.cancelledByName}' : '';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'This delivery memo has been CANCELLED$by.',
        style: pw.TextStyle(
            fontSize: 9,
            color: const PdfColor.fromInt(0xFFC62828),
            fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  String _joinNonEmpty(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join('   ');
}
