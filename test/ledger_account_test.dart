import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/utils/ledger_account.dart';

/// Built from the firm's real printed Ledger Account for DUDULWAR AGENCIES ARNI
/// (1-Apr-26 to 24-Jul-26). Every figure below is read off that statement, so
/// the test fails if our arithmetic stops matching Tally.
void main() {
  LedgerMovement dr(String d, String vt, String vn, double amt) =>
      LedgerMovement(
        date: DateTime.parse(d),
        voucherType: vt,
        voucherNo: vn,
        amount: amt,
        type: 'Dr',
        particulars: 'SEED SALE A/C',
      );
  LedgerMovement cr(String d, String vt, String vn, double amt, String p) =>
      LedgerMovement(
        date: DateTime.parse(d),
        voucherType: vt,
        voucherNo: vn,
        amount: amt,
        type: 'Cr',
        particulars: p,
      );

  final movements = <LedgerMovement>[
    cr('2026-04-30', 'Journal', '98', 315000, 'DUDULWAR AGENCY ARNI[B]'),
    dr('2026-05-01', 'SEED SALE', 'HS-13', 217800),
    dr('2026-05-06', 'SEED SALE', 'HS-75', 81775),
    dr('2026-05-12', 'SEED SALE', 'HS-356', 118950),
    dr('2026-05-22', 'SEED SALE', 'HS-836', 81100),
    cr('2026-05-22', 'RCT', '2574', 390000,
        'YAVATMAL URBAN CO-OP BANK HYPO A/C'),
    dr('2026-06-01', 'SEED SALE', 'HS-1700', 8465),
    cr('2026-06-04', 'Purchase', '170', 27030, 'SEED PURCHASE A/C'),
    cr('2026-06-25', 'Credit Note', '68', 14400, 'SEED SALE A/C'),
    cr('2026-07-12', 'Credit Note', '482', 94537, 'SEED SALE A/C'),
    cr('2026-07-23', 'Credit Note', '870', 960, 'SEED SALE A/C'),
  ];

  LedgerAccount build() => LedgerAccount.fromMovements(
        partyName: 'DUDULWAR AGENCIES ARNI',
        movements: movements,
        // Printed closing balance: Cr 3,44,642.00 -> negative under Dr-positive.
        closingSigned: -344642,
        from: DateTime.parse('2026-04-01'),
        to: DateTime.parse('2026-07-24'),
      );

  test('derives the opening balance the statement shows (Cr 10,805)', () {
    // Tally's $OpeningBalance is the financial-year figure, so this is derived
    // as closing minus the period's movements. It must land on the printed one.
    expect(build().openingSigned, closeTo(-10805, 0.001));
  });

  test('opening row is on the credit side, labelled By', () {
    final opening = build().rows.first;
    expect(opening.particulars, 'Opening Balance');
    expect(opening.prefix, 'By');
    expect(opening.credit, closeTo(10805, 0.001));
    expect(opening.debit, isNull);
  });

  test('column totals match the print (5,08,090 Dr / 8,52,732 Cr)', () {
    final a = build();
    expect(a.debitTotal, closeTo(508090, 0.001));
    expect(a.creditTotal, closeTo(852732, 0.001));
  });

  test('closing balance is the balancing figure, on the debit side', () {
    final a = build();
    expect(a.closesOnDebit, isTrue);
    expect(a.closingPrefix, 'To');
    expect(a.closingFigure, closeTo(344642, 0.001));
  });

  test('both columns foot to the same grand total', () {
    final a = build();
    expect(a.grandTotal, closeTo(852732, 0.001));
    final debitSide = a.debitTotal + (a.closesOnDebit ? a.closingFigure : 0);
    final creditSide = a.creditTotal + (a.closesOnDebit ? 0 : a.closingFigure);
    expect(debitSide, closeTo(creditSide, 0.001),
        reason: 'a ledger account that does not balance is not a statement');
    expect(debitSide, closeTo(a.grandTotal, 0.001));
  });

  test('repeated dates are blanked on continuation rows, like Tally', () {
    // Two movements fall on 22-May-26; the second must not reprint the date.
    final rows = build().rows;
    final may22 = rows
        .where((r) => r.voucherNo == 'HS-836' || r.voucherNo == '2574')
        .toList();
    expect(may22, hasLength(2));
    expect(may22.first.date, isNotNull);
    expect(may22.last.date, isNull);
  });

  test('To marks debits and By marks credits', () {
    final rows = build().rows;
    expect(rows.firstWhere((r) => r.voucherNo == 'HS-13').prefix, 'To');
    expect(rows.firstWhere((r) => r.voucherNo == '2574').prefix, 'By');
    expect(rows.firstWhere((r) => r.voucherNo == '482').prefix, 'By');
  });

  test('movements are ordered oldest first regardless of input order', () {
    final shuffled = movements.reversed.toList();
    final a = LedgerAccount.fromMovements(
      partyName: 'X',
      movements: shuffled,
      closingSigned: -344642,
      from: DateTime.parse('2026-04-01'),
    );
    final dated = a.rows.skip(1).where((r) => r.date != null).toList();
    for (var i = 1; i < dated.length; i++) {
      expect(dated[i].date!.isBefore(dated[i - 1].date!), isFalse);
    }
    expect(a.debitTotal, closeTo(508090, 0.001));
  });

  group('edge cases', () {
    test('a debit closing balance closes on the credit side', () {
      final a = LedgerAccount.fromMovements(
        partyName: 'X',
        movements: [dr('2026-04-02', 'SEED SALE', 'A-1', 5000)],
        closingSigned: 5000, // Dr — customer owes
      );
      expect(a.closesOnDebit, isFalse);
      expect(a.closingPrefix, 'By');
      expect(a.closingFigure, closeTo(5000, 0.001));
      expect(a.openingSigned, closeTo(0, 0.001));
    });

    test('no movements still produces a balanced account', () {
      final a = LedgerAccount.fromMovements(
        partyName: 'X',
        movements: const [],
        closingSigned: -2500,
      );
      expect(a.openingSigned, closeTo(-2500, 0.001));
      expect(a.rows, hasLength(1));
      expect(a.creditTotal, closeTo(2500, 0.001));
      expect(a.grandTotal, closeTo(2500, 0.001));
    });
  });
}
