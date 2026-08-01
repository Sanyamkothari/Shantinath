import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/utils/ledger_account.dart';

class ExcelExportService {
  ExcelExportService._();

  static final _dateFmt = DateFormat('d-MMM-yy');

  /// Exports the ledger as the firm's Tally "Ledger Account" sheet — same
  /// letterhead, same Date / Particulars / Vch Type / Vch No / Debit / Credit
  /// columns, same opening and balancing closing rows as the PDF.
  ///
  /// Both exports are driven from [LedgerAccount], so the numbers cannot drift
  /// apart. Amounts are written as real numbers, not text, so the sheet stays
  /// summable in Excel.
  static Future<void> exportLedger({
    required String firmName,
    required String proprietorName,
    required String phone,
    required List<Map<String, dynamic>> transactions,
    required double outstandingBalance,
    required String balanceType,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final movements = transactions.map((tx) {
        final type = (tx['type'] ?? 'Dr').toString();
        return LedgerMovement(
          date: tx['date'] as DateTime,
          voucherType: (tx['voucherType'] ?? '').toString(),
          voucherNo: (tx['voucherNo'] ?? '').toString(),
          amount: (tx['amount'] as num?)?.toDouble() ?? 0,
          type: type,
          particulars: (tx['particulars'] ?? '').toString(),
          narration: (tx['narration'] ?? '').toString(),
        );
      }).toList();

      final account = LedgerAccount.fromMovements(
        partyName: firmName,
        movements: movements,
        closingSigned:
            balanceType == 'Cr' ? -outstandingBalance : outstandingBalance,
        from: from,
        to: to,
      );

      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Ledger Account');
      final sheet = excel['Ledger Account'];

      CellStyle centred({bool bold = false, double size = 10}) => CellStyle(
            bold: bold,
            fontFamily: getFontFamily(FontFamily.Arial),
            fontSize: size.toInt(),
            horizontalAlign: HorizontalAlign.Center,
          );
      final headerStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#2E7D32'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
      final rightBold = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Right,
      );
      final right = CellStyle(
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Right,
      );

      var r = 0;
      void put(int col, int row, CellValue v, [CellStyle? style]) {
        final c = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        c.value = v;
        if (style != null) c.cellStyle = style;
      }

      // 1. Letterhead — matches the PDF: address, licences, e-mail. No GSTIN,
      //    state code or phone, which the Tally statement print also omits.
      for (final line in <String>[
        AppConstants.sellerName,
        AppConstants.sellerAddress,
        if (AppConstants.sellerSeedLicence.isNotEmpty)
          'Seed Licence No.:${AppConstants.sellerSeedLicence}',
        if (AppConstants.sellerSeedLicence2.isNotEmpty)
          'Seed Licence No: ${AppConstants.sellerSeedLicence2}',
        if (AppConstants.sellerFertilizerWholesaleLicence.isNotEmpty)
          'Fertilizer Wholesale Lic No : ${AppConstants.sellerFertilizerWholesaleLicence}',
        if (AppConstants.sellerFertilizerRetailLicence.isNotEmpty)
          'Fertilizer Retail Lic. NO.: ${AppConstants.sellerFertilizerRetailLicence}',
        if (AppConstants.sellerEmail.isNotEmpty)
          'E-Mail : ${AppConstants.sellerEmail}',
      ]) {
        put(0, r, TextCellValue(line), centred(bold: r == 0, size: r == 0 ? 14 : 10));
        r++;
      }

      r++;
      put(0, r++, TextCellValue(account.partyName), centred(bold: true, size: 12));
      put(0, r++, TextCellValue('Ledger Account'), centred());
      if (proprietorName.isNotEmpty || phone.isNotEmpty) {
        put(
            0,
            r++,
            TextCellValue([proprietorName, phone]
                .where((s) => s.isNotEmpty)
                .join('  •  ')),
            centred());
      }
      put(
          0,
          r++,
          TextCellValue(
              '${_dateFmt.format(account.from)} to ${_dateFmt.format(account.to)}'),
          centred());
      r++;

      // 2. Column headings
      const headers = [
        'Date',
        '',
        'Particulars',
        'Vch Type',
        'Vch No.',
        'Debit',
        'Credit'
      ];
      for (var c = 0; c < headers.length; c++) {
        put(c, r, TextCellValue(headers[c]), headerStyle);
      }
      r++;

      sheet.setColumnWidth(0, 12);
      sheet.setColumnWidth(1, 4);
      sheet.setColumnWidth(2, 42);
      sheet.setColumnWidth(3, 14);
      sheet.setColumnWidth(4, 12);
      sheet.setColumnWidth(5, 16);
      sheet.setColumnWidth(6, 16);

      // 3. Opening balance, movements, then the balancing close
      for (final row in account.rows) {
        put(0, r, TextCellValue(row.date == null ? '' : _dateFmt.format(row.date!)));
        put(1, r, TextCellValue(row.prefix));
        put(2, r, TextCellValue(row.particulars));
        put(3, r, TextCellValue(row.voucherType));
        put(4, r, TextCellValue(row.voucherNo));
        if (row.debit != null) put(5, r, DoubleCellValue(row.debit!), right);
        if (row.credit != null) put(6, r, DoubleCellValue(row.credit!), right);
        r++;
      }

      put(5, r, DoubleCellValue(account.debitTotal), rightBold);
      put(6, r, DoubleCellValue(account.creditTotal), rightBold);
      r++;

      put(1, r, TextCellValue(account.closingPrefix));
      put(2, r, TextCellValue('Closing Balance'), CellStyle(bold: true));
      put(account.closesOnDebit ? 5 : 6, r,
          DoubleCellValue(account.closingFigure), rightBold);
      r++;

      put(5, r, DoubleCellValue(account.grandTotal), rightBold);
      put(6, r, DoubleCellValue(account.grandTotal), rightBold);

      // 4. Save and share
      final bytes = excel.save();
      if (bytes == null) {
        throw Exception('Failed to generate Excel file bytes.');
      }

      final directory = await getTemporaryDirectory();
      final sanitizedFirm =
          firmName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
      final filePath =
          '${directory.path}/Ledger_${sanitizedFirm}_${DateFormat('ddMMyy').format(DateTime.now())}.xlsx';

      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Ledger Account for $firmName - ${AppConstants.sellerName}',
      );
    } catch (e) {
      debugPrint('Excel Export Error: $e');
      throw Exception('Excel Export Error: $e');
    }
  }
}
