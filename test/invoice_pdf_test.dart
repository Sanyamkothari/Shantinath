import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/services/invoice_pdf_service.dart';

/// Renders the invoice PDF end to end. The point is to catch layout failures —
/// the `pdf` package throws when content overflows a fixed `Page`, so a bill
/// with many lines is the case that matters.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<InvoiceLine> lines(int n) => List.generate(
        n,
        (i) => InvoiceLine(
          description: 'ROCKY BG-II 3434 HY COTTON DAFTARI 475 GMS #$i',
          batch: '${3468 + i}',
          hsn: '1209',
          qty: 10,
          unit: 'BAGS',
          rate: 750,
          amount: 7500,
        ),
      );

  /// Pulls the drawable text out of a PDF so we can assert what actually got
  /// painted. A fixed-size Page silently clips overflow — it does not throw —
  /// so "the build succeeded" proves nothing about the last line item.
  String drawnText(List<int> bytes) {
    final raw = Uint8List.fromList(bytes);
    final out = BytesBuilder();
    final pattern = RegExp(r'stream\r?\n', multiLine: true);
    final s = latin1.decode(raw, allowInvalid: true);
    for (final m in pattern.allMatches(s)) {
      final end = s.indexOf('endstream', m.end);
      if (end < 0) continue;
      try {
        out.add(zlib.decode(latin1.encode(s.substring(m.end, end))));
      } catch (_) {
        // not a deflated stream; ignore
      }
    }
    return latin1
        .decode(out.toBytes(), allowInvalid: true)
        .replaceAll(RegExp(r'[^\x20-\x7e]'), '');
  }

  Future<Uint8List> render(int itemCount, String outName) async {
    final bytes = await InvoicePdfService().build(
      partyName: 'MEGHAVAT KRISHI KENDRA KANDHRI',
      invoiceNo: 'HS-947',
      refNo: '200',
      date: DateTime(2026, 5, 24),
      items: lines(itemCount),
      total: 7500.0 * itemCount,
      partyGstNo: '27ABCDE1234F1Z5',
    );
    final f = File('build/test_$outName.pdf');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return bytes;
  }

  /// Every line item, the grand total and the signatory block must appear.
  Future<void> expectComplete(int n, String outName, String grandTotal) async {
    final bytes = await render(n, outName);
    final text = drawnText(bytes);

    for (final i in [0, n ~/ 2, n - 1]) {
      expect(text, contains('#$i'),
          reason: 'line item #$i of $n is missing from the rendered PDF — '
              'the goods table is being clipped, which would ship a tax '
              'invoice that omits goods while still showing a correct total');
    }
    expect(text, contains(grandTotal), reason: 'grand total missing');
    expect(text, contains('Authorised'), reason: 'signatory block missing');
  }

  test('renders a 1-line invoice complete', () async {
    await expectComplete(1, 'invoice_1', '7,500.00');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('renders the reference 3-line invoice complete', () async {
    await expectComplete(3, 'invoice_3', '22,500.00');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a 40-line invoice keeps every item (paginates, never clips)', () async {
    await expectComplete(40, 'invoice_40', '3,00,000.00');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
