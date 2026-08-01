/// Builds the Tally "Ledger Account" view of a statement — opening balance,
/// To/By rows, column totals and the balancing closing figure.
///
/// Shared by the PDF and Excel exports so the two can never disagree about the
/// numbers. Sign convention throughout: **Dr positive, Cr negative**.
library;

/// One statement movement, independent of the Firestore shape each screen uses.
class LedgerMovement {
  final DateTime date;
  final String voucherType;
  final String voucherNo;
  final double amount;
  final String type; // 'Dr' | 'Cr'
  final String particulars;
  final String narration;

  const LedgerMovement({
    required this.date,
    required this.amount,
    required this.type,
    this.voucherType = '',
    this.voucherNo = '',
    this.particulars = '',
    this.narration = '',
  });

  bool get isDr => type != 'Cr';

  /// Dr positive, Cr negative.
  double get signed => isDr ? amount : -amount;
}

/// A printable row. `date` is null on continuation rows — Tally prints the date
/// only when it changes from the row above.
class LedgerAccountRow {
  final DateTime? date;
  final String prefix; // 'To' (debit) | 'By' (credit)
  final String particulars;
  final String voucherType;
  final String voucherNo;
  final double? debit;
  final double? credit;
  final String narration;

  const LedgerAccountRow({
    required this.prefix,
    required this.particulars,
    this.date,
    this.voucherType = '',
    this.voucherNo = '',
    this.debit,
    this.credit,
    this.narration = '',
  });
}

class LedgerAccount {
  final String partyName;
  final DateTime from;
  final DateTime to;

  /// Signed balance before the first movement in this window.
  final double openingSigned;

  /// Signed balance after the last movement.
  final double closingSigned;

  final List<LedgerAccountRow> rows;

  /// Column totals INCLUDING the opening balance, excluding the closing figure.
  final double debitTotal;
  final double creditTotal;

  const LedgerAccount({
    required this.partyName,
    required this.from,
    required this.to,
    required this.openingSigned,
    required this.closingSigned,
    required this.rows,
    required this.debitTotal,
    required this.creditTotal,
  });

  /// The closing balance is the figure that squares the two columns, and it is
  /// printed on the *lighter* side. A credit closing balance (customer in
  /// credit) therefore appears under Debit, which is what makes both columns
  /// foot to the same grand total.
  bool get closesOnDebit => creditTotal > debitTotal;
  double get closingFigure => (creditTotal - debitTotal).abs();
  double get grandTotal => debitTotal > creditTotal ? debitTotal : creditTotal;

  /// 'To Closing Balance' when it sits on the debit side, else 'By'.
  String get closingPrefix => closesOnDebit ? 'To' : 'By';
  String get openingPrefix => openingSigned >= 0 ? 'To' : 'By';

  /// Builds the account from movements plus the CURRENT closing balance.
  ///
  /// The opening balance is derived — `closing − Σ movements` — rather than
  /// pulled from Tally, because Tally's `$OpeningBalance` is the figure at the
  /// start of the financial year, which does not match an arbitrary sync window.
  /// Deriving it keeps the statement internally consistent for whatever range
  /// was actually synced.
  ///
  /// [closingSigned] is Dr-positive; pass `balanceType == 'Cr' ? -balance : balance`.
  factory LedgerAccount.fromMovements({
    required String partyName,
    required List<LedgerMovement> movements,
    required double closingSigned,
    DateTime? from,
    DateTime? to,
  }) {
    final sorted = [...movements]..sort((a, b) => a.date.compareTo(b.date));
    final net = sorted.fold<double>(0, (s, m) => s + m.signed);
    final openingSigned = closingSigned - net;

    final rows = <LedgerAccountRow>[];
    DateTime? lastDate;

    final start = from ?? (sorted.isNotEmpty ? sorted.first.date : DateTime.now());
    rows.add(LedgerAccountRow(
      date: start,
      prefix: openingSigned >= 0 ? 'To' : 'By',
      particulars: 'Opening Balance',
      debit: openingSigned > 0 ? openingSigned : null,
      credit: openingSigned < 0 ? -openingSigned : null,
    ));
    lastDate = _dayOf(start);

    for (final m in sorted) {
      final day = _dayOf(m.date);
      final repeats = lastDate != null && day == lastDate;
      rows.add(LedgerAccountRow(
        date: repeats ? null : m.date,
        prefix: m.isDr ? 'To' : 'By',
        particulars: m.particulars,
        voucherType: m.voucherType,
        voucherNo: m.voucherNo,
        debit: m.isDr ? m.amount : null,
        credit: m.isDr ? null : m.amount,
        narration: m.narration,
      ));
      lastDate = day;
    }

    var debitTotal = openingSigned > 0 ? openingSigned : 0.0;
    var creditTotal = openingSigned < 0 ? -openingSigned : 0.0;
    for (final m in sorted) {
      if (m.isDr) {
        debitTotal += m.amount;
      } else {
        creditTotal += m.amount;
      }
    }

    return LedgerAccount(
      partyName: partyName,
      from: start,
      to: to ?? (sorted.isNotEmpty ? sorted.last.date : start),
      openingSigned: openingSigned,
      closingSigned: closingSigned,
      rows: rows,
      debitTotal: debitTotal,
      creditTotal: creditTotal,
    );
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
}
