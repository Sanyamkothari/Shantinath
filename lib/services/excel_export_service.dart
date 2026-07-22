import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExcelExportService {
  ExcelExportService._();

  /// Export ledger transactions to Excel (.xlsx) file and open the share dialog.
  static Future<void> exportLedger({
    required String firmName,
    required String proprietorName,
    required String phone,
    required List<Map<String, dynamic>> transactions,
    required double outstandingBalance,
    required String balanceType,
  }) async {
    try {
      final excel = Excel.createExcel();
      
      // Rename default sheet
      final String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Ledger Statement');
      final sheet = excel['Ledger Statement'];

      // Setup styling
      final headerStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 11,
        backgroundColorHex: ExcelColor.fromHexString('#2E7D32'), // Shantinath Green
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

      final titleStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 16,
        fontColorHex: ExcelColor.fromHexString('#1B5E20'),
      );

      final metaLabelStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 10,
        backgroundColorHex: ExcelColor.fromHexString('#F5F5F0'),
      );

      final metaValueStyle = CellStyle(
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 10,
      );

      final totalStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 11,
        backgroundColorHex: ExcelColor.fromHexString('#E8F5E9'), // Light green
        horizontalAlign: HorizontalAlign.Right,
      );

      // 1. Title Block
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('SHANTINATH AGRO AGENCY');
      sheet.cell(CellIndex.indexByString('A1')).cellStyle = titleStyle;
      
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Customer Account Ledger Statement');
      sheet.cell(CellIndex.indexByString('A2')).cellStyle = CellStyle(
        italic: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 11,
      );

      // 2. Metadata Block
      sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Firm Name:');
      sheet.cell(CellIndex.indexByString('A4')).cellStyle = metaLabelStyle;
      sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(firmName);
      sheet.cell(CellIndex.indexByString('B4')).cellStyle = metaValueStyle;

      sheet.cell(CellIndex.indexByString('A5')).value = TextCellValue('Proprietor:');
      sheet.cell(CellIndex.indexByString('A5')).cellStyle = metaLabelStyle;
      sheet.cell(CellIndex.indexByString('B5')).value = TextCellValue(proprietorName);
      sheet.cell(CellIndex.indexByString('B5')).cellStyle = metaValueStyle;

      sheet.cell(CellIndex.indexByString('D4')).value = TextCellValue('Phone Number:');
      sheet.cell(CellIndex.indexByString('D4')).cellStyle = metaLabelStyle;
      sheet.cell(CellIndex.indexByString('E4')).value = TextCellValue(phone);
      sheet.cell(CellIndex.indexByString('E4')).cellStyle = metaValueStyle;

      sheet.cell(CellIndex.indexByString('D5')).value = TextCellValue('Export Date:');
      sheet.cell(CellIndex.indexByString('D5')).cellStyle = metaLabelStyle;
      sheet.cell(CellIndex.indexByString('E5')).value = TextCellValue(
        DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now()),
      );
      sheet.cell(CellIndex.indexByString('E5')).cellStyle = metaValueStyle;

      sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Outstanding:');
      sheet.cell(CellIndex.indexByString('A6')).cellStyle = metaLabelStyle;
      sheet.cell(CellIndex.indexByString('B6')).value = TextCellValue(
        '₹ ${outstandingBalance.toStringAsFixed(2)} ($balanceType)',
      );
      sheet.cell(CellIndex.indexByString('B6')).cellStyle = CellStyle(
        bold: true,
        fontFamily: getFontFamily(FontFamily.Arial),
        fontSize: 11,
        fontColorHex: balanceType == 'Dr'
            ? ExcelColor.fromHexString('#C62828')
            : ExcelColor.fromHexString('#2E7D32'),
      );

      // 3. Transactions Table Header
      final headers = [
        'Date',
        'Voucher Type',
        'Voucher No',
        'Particulars',
        'Narration',
        'Debit (Owed/Dr)',
        'Credit (Paid/Cr)'
      ];

      const startRow = 8;
      for (var col = 0; col < headers.length; col++) {
        final cellIndex = CellIndex.indexByColumnRow(columnIndex: col, rowIndex: startRow);
        sheet.cell(cellIndex).value = TextCellValue(headers[col]);
        sheet.cell(cellIndex).cellStyle = headerStyle;
      }

      // Set column widths
      sheet.setColumnWidth(0, 15.0); // Date
      sheet.setColumnWidth(1, 15.0); // Voucher Type
      sheet.setColumnWidth(2, 12.0); // Voucher No
      sheet.setColumnWidth(3, 25.0); // Particulars
      sheet.setColumnWidth(4, 35.0); // Narration
      sheet.setColumnWidth(5, 18.0); // Debit
      sheet.setColumnWidth(6, 18.0); // Credit

      // 4. Data Rows
      double totalDebit = 0.0;
      double totalCredit = 0.0;

      final dateFormat = DateFormat('dd-MMM-yyyy');

      for (var i = 0; i < transactions.length; i++) {
        final tx = transactions[i];
        final row = startRow + 1 + i;

        final DateTime dateVal = tx['date'] as DateTime;
        final String voucherType = tx['voucherType'].toString();
        final String voucherNo = tx['voucherNo'].toString();
        final String particulars = tx['particulars'].toString();
        final String narration = tx['narration'].toString();
        final double amount = tx['amount'] as double;
        final String type = tx['type'].toString(); // 'Dr' or 'Cr'

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = 
            TextCellValue(dateFormat.format(dateVal));
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = 
            TextCellValue(voucherType);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = 
            TextCellValue(voucherNo);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = 
            TextCellValue(particulars);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = 
            TextCellValue(narration);

        // Debit / Credit column alignment
        if (type == 'Dr') {
          totalDebit += amount;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
              DoubleCellValue(amount);
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = 
              TextCellValue('-');
        } else {
          totalCredit += amount;
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = 
              TextCellValue('-');
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = 
              DoubleCellValue(amount);
        }

        // Align right for amounts
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).cellStyle = 
            CellStyle(horizontalAlign: HorizontalAlign.Right);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).cellStyle = 
            CellStyle(horizontalAlign: HorizontalAlign.Right);
      }

      // 5. Total Row
      final totalRow = startRow + 1 + transactions.length;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: totalRow)).value = 
          TextCellValue('Total Transactions:');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: totalRow)).cellStyle = totalStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow)).value = 
          DoubleCellValue(totalDebit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow)).cellStyle = totalStyle;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: totalRow)).value = 
          DoubleCellValue(totalCredit);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: totalRow)).cellStyle = totalStyle;

      // 6. Save and Share Excel file
      final bytes = excel.save();
      if (bytes == null) {
        throw Exception('Failed to generate Excel file bytes.');
      }

      final directory = await getTemporaryDirectory();
      final sanitizedFirm = firmName.replaceAll(RegExp(r'[^\w\s\-]'), '').replaceAll(' ', '_');
      final filePath = '${directory.path}/Ledger_${sanitizedFirm}_${DateFormat('ddMMyy').format(DateTime.now())}.xlsx';
      
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      // Trigger standard share dialog
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Ledger Statement for $firmName - Shantinath Agro Agency',
      );
    } catch (e) {
      debugPrint('Excel Export Error: $e');
      throw Exception('Excel Export Error: $e');
    }
  }
}
