import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Shares PDF files directly via the native OS share sheet (WhatsApp, Email, etc.),
/// matching the seamless 1-tap Excel export behavior.
Future<void> shareOrDownloadPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  try {
    if (kIsWeb) {
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: filename,
      );
    } else {
      final dir = await getTemporaryDirectory();
      final sanitized = filename.replaceAll(RegExp(r'[^\w\s\.\-]'), '_');
      final file = File('${dir.path}/$sanitized');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: filename,
      );
    }
  } catch (e) {
    debugPrint('Error sharing PDF: $e');
    if (!kIsWeb) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    }
  }
}
