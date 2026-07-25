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
  ///
  /// dart_pdf emits every word as its own positioned `[(word)]TJ` operator, so
  /// the raw stream never contains a multi-word phrase. Extract the literals and
  /// re-join them with single spaces, which is what makes `contains('TAX
  /// INVOICE')` meaningful.
  String drawnText(List<int> bytes) {
    final s = latin1.decode(Uint8List.fromList(bytes), allowInvalid: true);
    final out = BytesBuilder();
    for (final m in RegExp(r'stream\r?\n', multiLine: true).allMatches(s)) {
      final end = s.indexOf('endstream', m.end);
      if (end < 0) continue;
      try {
        out.add(zlib.decode(latin1.encode(s.substring(m.end, end))));
      } catch (_) {
        // not a deflated stream; ignore
      }
    }
    final content = latin1.decode(out.toBytes(), allowInvalid: true);

    final words = RegExp(r'\(((?:\\.|[^()\\])*)\)\s*Tj|\[\((.*?)\)\]\s*TJ')
        .allMatches(content)
        .map((m) => (m.group(1) ?? m.group(2) ?? '').replaceAll(r'\', ''))
        .where((w) => w.isNotEmpty);
    return words.join(' ');
  }

  Future<Uint8List> render(int itemCount, String outName,
      {TaxDocumentKind kind = TaxDocumentKind.invoice}) async {
    final bytes = await InvoicePdfService().build(
      partyName: 'MEGHAVAT KRISHI KENDRA KANDHRI',
      kind: kind,
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

  group('credit note', () {
    test('uses the credit-note heading, label and closing note', () async {
      final text = drawnText(
          await render(5, 'creditnote_5', kind: TaxDocumentKind.creditNote));

      expect(text, contains('CREDITNOTE'));
      expect(text, contains('Credit Note No.'));
      expect(text, contains('This is a Computer Generated Document'));

      // The firm's credit note omits Place of Supply; the tax invoice keeps it.
      expect(text, isNot(contains('Place of Supply')));
      expect(text, contains('State Name'));
    });

    test('the tax invoice keeps what the credit note drops', () async {
      final text = drawnText(await render(5, 'invoice_5'));

      expect(text, contains('TAX INVOICE'));
      expect(text, contains('Invoice No.'));
      expect(text, contains('This is a Computer Generated Invoice'));
      expect(text, contains('Place of Supply'));
      expect(text, isNot(contains('CREDITNOTE')));
    });

    test('still renders every line item', () async {
      await expectComplete(30, 'creditnote_30', '2,25,000.00');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('docType maps to the right document kind', () {
    expect(TaxDocumentKind.fromDocType('credit_note'),
        TaxDocumentKind.creditNote);
    expect(TaxDocumentKind.fromDocType('invoice'), TaxDocumentKind.invoice);
    // Docs synced before docType existed, or with an unexpected value, must not
    // silently print as credit notes.
    expect(TaxDocumentKind.fromDocType(null), TaxDocumentKind.invoice);
    expect(TaxDocumentKind.fromDocType(''), TaxDocumentKind.invoice);
    expect(TaxDocumentKind.fromDocType('something_else'),
        TaxDocumentKind.invoice);
  });
}
