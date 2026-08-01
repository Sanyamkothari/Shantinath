import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Helper to download or preview/print PDF files seamlessly across Web and Mobile.
///
/// Uses [Printing.layoutPdf] on all platforms (Web, Android, iOS), which opens
/// the native/browser PDF preview modal with built-in "Save as PDF", "Download",
/// and "Print" actions.
Future<void> shareOrDownloadPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  try {
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: filename,
    );
  } catch (e) {
    debugPrint('Error layout/download PDF: $e');
    // Fallback to sharePdf on mobile if layoutPdf fails
    if (!kIsWeb) {
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    }
  }
}
