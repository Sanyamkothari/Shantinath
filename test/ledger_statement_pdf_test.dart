import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/services/ledger_statement_pdf_service.dart';

/// Renders the Ledger Account PDF and asserts against what was actually painted.
/// dart_pdf clips silently rather than throwing, so a successful build proves
/// nothing about the last row or the closing figures.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String drawnText(List<int> bytes) {
    final s = latin1.decode(Uint8List.fromList(bytes), allowInvalid: true);
    final out = BytesBuilder();
    for (final m in RegExp(r'stream\r?\n', multiLine: true).allMatches(s)) {
      final end = s.indexOf('endstream', m.end);
      if (end < 0) continue;
      try {
        out.add(zlib.decode(latin1.encode(s.substring(m.end, end))));
      } catch (_) {
        // not a deflated stream
      }
    }
    final content = latin1.decode(out.toBytes(), allowInvalid: true);
    return RegExp(r'\(((?:\\.|[^()\\])*)\)\s*Tj|\[\((.*?)\)\]\s*TJ')
        .allMatches(content)
        .map((m) => (m.group(1) ?? m.group(2) ?? '').replaceAll(r'\', ''))
        .where((w) => w.isNotEmpty)
        .join(' ');
  }

  List<LedgerStatementEntry> entries(int n) => List.generate(
        n,
        (i) => LedgerStatementEntry(
          date: DateTime(2026, 5, 1).add(Duration(days: i)),
          voucherType: 'SEED SALE',
          voucherNo: 'HS-$i',
          amount: 1000,
          type: i.isEven ? 'Dr' : 'Cr',
          particulars: 'SEED SALE A/C',
        ),
      );

  Future<Uint8List> render(int n, String out) async {
    final bytes = await LedgerStatementPdfService().build(
      title: 'DUDULWAR AGENCIES ARNI',
      outstandingBalance: 344642,
      balanceType: 'Cr',
      entries: entries(n),
    );
    final f = File('build/test_$out.pdf');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return bytes;
  }

  test('carries the Tally letterhead, party and Ledger Account caption',
      () async {
    final t = drawnText(await render(11, 'statement_11'));
    expect(t, contains('SHANTINATH AGRO AGENCIES ARNI 2024-2027'));
    expect(t, contains('DUDULWAR AGENCIES ARNI'));
    expect(t, contains('Ledger Account'));
    // The statement letterhead omits GSTIN and phone, unlike the tax invoice.
    expect(t, isNot(contains('GSTIN/UIN')));
    expect(t, isNot(contains('Contact :')));
  });

  test('prints the Tally column headings', () async {
    final t = drawnText(await render(11, 'statement_11'));
    for (final h in ['Date', 'Particulars', 'Vch Type', 'Vch No.', 'Debit',
      'Credit']) {
      expect(t, contains(h), reason: 'missing column heading $h');
    }
  });

  test('opens with a brought-forward balance and closes with the balancer',
      () async {
    final t = drawnText(await render(11, 'statement_11'));
    expect(t, contains('Opening Balance'));
    expect(t, contains('Closing Balance'));
  });

  test('a long statement paginates and keeps every row', () async {
    final bytes = await render(120, 'statement_120');
    final t = drawnText(bytes);
    for (final i in [0, 60, 119]) {
      expect(t, contains('HS-$i'),
          reason: 'row HS-$i was clipped — a statement that drops movements '
              'still foots correctly and is therefore silently wrong');
    }
    expect(t, contains('Closing Balance'));

    final pages = RegExp(r'/Type\s*/Page[^s]')
        .allMatches(latin1.decode(bytes, allowInvalid: true))
        .length;
    expect(pages, greaterThan(1), reason: '120 rows must not fit one page');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
