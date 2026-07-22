import 'dart:io';
import 'package:share_plus/share_plus.dart';

/// Helper utility for creating and sharing CSV documents.
class CsvExportHelper {
  CsvExportHelper._();

  /// Converts a header list and double-nested row data into a formatted CSV string.
  /// Properly escapes internal quotes and handles commas or newlines.
  static String convertToCsv(List<String> headers, List<List<dynamic>> rows) {
    final buffer = StringBuffer();

    // Write header line
    buffer.writeln(headers.map((h) => _escapeCsvValue(h)).join(','));

    // Write row lines
    for (final row in rows) {
      buffer.writeln(row.map((val) {
        if (val == null) return '';
        return _escapeCsvValue(val.toString());
      }).join(','));
    }

    return buffer.toString();
  }

  /// Escapes CSV values conforming to RFC 4180.
  /// If the value contains commas, quotes, or newlines, it will wrap the value
  /// in double quotes, and duplicate any existing double quotes.
  static String _escapeCsvValue(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      final escapedValue = value.replaceAll('"', '""');
      return '"$escapedValue"';
    }
    return value;
  }

  /// Writes a CSV string to a temporary file and triggers the native OS sharing sheet.
  static Future<void> exportAndShareCsv({
    required String fileName,
    required String csvContent,
  }) async {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(csvContent);

    final xFile = XFile(
      file.path,
      mimeType: 'text/csv',
      name: fileName,
    );

    await Share.shareXFiles(
      [xFile],
      subject: fileName.replaceAll('.csv', '').replaceAll('_', ' '),
    );
  }
}
