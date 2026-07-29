import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shantinath_agro/services/invoice_pdf_service.dart';
import 'package:shantinath_agro/utils/pdf_helper.dart';

/// Shows one sales invoice (bill) in full — line items + charges + total — with
/// Download / Send actions. Data is the synced `tally_ledgers/{id}/invoices` doc.
class InvoiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final String partyName;
  final String partyVillage;
  final String partyPhone;
  final String partyGstNo;

  const InvoiceDetailScreen({
    super.key,
    required this.invoice,
    required this.partyName,
    this.partyVillage = '',
    this.partyPhone = '',
    this.partyGstNo = '',
  });

  static const Color _green = Color(0xFF2E7D32);

  final _currency = const _Cur();

  static double _num(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) {
      final clean = val.replaceAll(RegExp(r'[^0-9.-]'), '');
      return double.tryParse(clean) ?? 0.0;
    }
    return 0.0;
  }

  DateTime get _date {
    final d = invoice['date'];
    if (d is Timestamp) return d.toDate();
    if (d is DateTime) return d;
    if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
    return DateTime.now();
  }

  List<Map<String, dynamic>> get _items =>
      ((invoice['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<Map<String, dynamic>> get _ledgers =>
      ((invoice['ledgers'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// Sales bill or credit note. Documents synced before `docType` existed have
  /// no value and are treated as invoices.
  TaxDocumentKind get _kind =>
      TaxDocumentKind.fromDocType(invoice['docType'] as String?);

  double get _taxable => _num(invoice['taxableValue']);
  double get _total => _num(invoice['total']);

  /// Synced line items mapped to the PDF's row model. `hsn` and `batch` stay
  /// empty until the Tally sync backfills them; the columns render blank rather
  /// than collapsing, so the layout matches the printed invoice either way.
  List<InvoiceLine> get _invoiceLines => _items
      .map((it) => InvoiceLine(
            description: (it['item'] ?? '').toString(),
            batch: (it['batch'] ?? '').toString(),
            hsn: (it['hsn'] ?? '').toString(),
            qty: _num(it['qty']),
            unit: (it['unit'] ?? '').toString(),
            rate: _num(it['rate']),
            amount: _num(it['amount']),
          ))
      .toList();

  Future<void> _share(BuildContext context) async {
    try {
      final bytes = await InvoicePdfService().build(
        partyName: partyName,
        partyAddress: partyVillage,
        partyGstNo: partyGstNo,
        kind: _kind,
        invoiceNo: (invoice['voucherNo'] ?? '').toString(),
        refNo: (invoice['refNo'] ?? '').toString(),
        date: _date,
        items: _invoiceLines,
        total: _total,
      );
      final no = (invoice['voucherNo'] ?? 'bill')
          .toString()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final prefix =
          _kind == TaxDocumentKind.creditNote ? 'CreditNote' : 'Invoice';
      await shareOrDownloadPdf(bytes: bytes, filename: '${prefix}_$no.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
              'Could not build ${_kind == TaxDocumentKind.creditNote ? 'credit note' : 'invoice'}: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vNo = (invoice['voucherNo'] ?? '').toString();
    final isCredit = _kind == TaxDocumentKind.creditNote;
    final vType =
        (invoice['voucherType'] ?? (isCredit ? 'Credit Note' : 'Invoice'))
            .toString();
    final charges = _chargeLedgers();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text('${isCredit ? 'Credit Note' : 'Invoice'} #$vNo',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download / Send',
            onPressed: () => _share(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vType,
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(partyName,
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(
                  [
                    if (partyVillage.isNotEmpty) partyVillage,
                    if (partyPhone.isNotEmpty) partyPhone,
                    DateFormat('dd MMM yyyy').format(_date),
                  ].join('  •  '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _itemHeader(),
                for (final it in _items) _itemRow(it),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _card(
            child: Column(
              children: [
                _totalRow('Taxable value', _currency.f(_taxable)),
                for (final c in charges)
                  _totalRow((c['ledger'] ?? 'Charge').toString(),
                      _currency.f(_num(c['amount']))),
                const Divider(),
                _totalRow('Grand Total', _currency.f(_total), bold: true),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _share(context),
        backgroundColor: _green,
        icon: const Icon(Icons.share_rounded, color: Colors.white),
        label: const Text('Download / Send',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Extra charge lines (hamali, freight, tax) — every ledger on the side
  /// opposite the party, minus the main goods ledger, which is identified as the
  /// one closest to the taxable value.
  ///
  /// The side matters: on a sales bill the party is debited so goods and charges
  /// sit on Cr, but on a credit note the party is credited and they sit on Dr.
  /// Taking Cr unconditionally would list the party's own posting as a charge.
  List<Map<String, dynamic>> _chargeLedgers() {
    final side = _kind == TaxDocumentKind.creditNote ? 'Dr' : 'Cr';
    final counter = _ledgers.where((l) => l['type'] == side).toList();
    Map<String, dynamic>? goods;
    double best = double.infinity;
    for (final l in counter) {
      final d = (_num(l['amount']) - _taxable).abs();
      if (d < best) {
        best = d;
        goods = l;
      }
    }
    return counter.where((l) => !identical(l, goods)).toList();
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  Widget _itemHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(
          children: [
            const Expanded(
                flex: 4,
                child: Text('Item',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
            const Expanded(
                flex: 2,
                child: Text('Qty',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
            const Expanded(
                flex: 2,
                child: Text('Amount',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700))),
          ],
        ),
      );

  Widget _itemRow(Map<String, dynamic> it) {
    final qty = _num(it['qty']);
    final rate = _num(it['rate']);
    final amount = _num(it['amount']);
    final unit = (it['unit'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((it['item'] ?? '').toString(),
                    style: GoogleFonts.outfit(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text('@ ${_currency.f(rate)}',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${_currency.q(qty)} $unit'.trim(),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(_currency.f(amount),
                textAlign: TextAlign.right,
                style: GoogleFonts.outfit(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: bold ? 15 : 13,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                      color: bold ? const Color(0xFF1B1B1B) : Colors.grey.shade700)),
            ),
            Text(value,
                style: GoogleFonts.outfit(
                    fontSize: bold ? 15 : 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold ? _green : const Color(0xFF1B1B1B))),
          ],
        ),
      );
}

/// Tiny currency/qty formatter holder (const-constructible for use in fields).
class _Cur {
  const _Cur();
  String f(double v) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
          .format(v);
  String q(double v) => NumberFormat('#,##0.##', 'en_IN').format(v);
}
