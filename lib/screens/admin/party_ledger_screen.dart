import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shantinath_agro/services/ledger_statement_pdf_service.dart';
import 'package:shantinath_agro/services/excel_export_service.dart';
import 'package:shantinath_agro/screens/admin/invoice_detail_screen.dart';
import 'package:shantinath_agro/services/invoice_pdf_service.dart';
import 'package:shantinath_agro/utils/pdf_helper.dart';

import 'package:shantinath_agro/widgets/tally_last_updated_header.dart';

/// Admin drill-down for one Tally customer, reached from the Ledger Book.
/// Two tabs: an account **Statement** (running balance, PDF/Excel) and **Bills**
/// (the shop's sales invoices — tap to view & send). Read-only; data comes from
/// `tally_ledgers/{docId}/transactions` and `.../invoices`.
class PartyLedgerScreen extends StatefulWidget {
  final String ledgerName;
  final String docId;
  final String village;
  final String phone;
  final String gstNo;
  final double balance;
  final String balanceType; // 'Dr' | 'Cr'

  const PartyLedgerScreen({
    super.key,
    required this.ledgerName,
    required this.docId,
    required this.balance,
    required this.balanceType,
    this.village = '',
    this.phone = '',
    this.gstNo = '',
  });

  @override
  State<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends State<PartyLedgerScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _drRed = Color(0xFFC62828);

  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  // The transactions currently rendered — captured for export.
  List<Map<String, dynamic>> _statementTxns = [];

  CollectionReference<Map<String, dynamic>> get _txnsRef =>
      FirebaseFirestore.instance
          .collection('tally_ledgers')
          .doc(widget.docId)
          .collection('transactions');

  CollectionReference<Map<String, dynamic>> get _invoicesRef =>
      FirebaseFirestore.instance
          .collection('tally_ledgers')
          .doc(widget.docId)
          .collection('invoices');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F0),
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.ledgerName,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          // The global tabBarTheme is tuned for tabs on a light surface
          // (labelColor: primaryGreen), which renders green-on-green here.
          // Override to white like every other TabBar sitting on the AppBar.
          bottom: TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: GoogleFonts.outfit(
              fontWeight: FontWeight.w400,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Statement'),
              Tab(text: 'Bills'),
              Tab(text: 'Credit Notes'),
            ],
          ),
        ),
        body: Column(
          children: [
            const TallyLastUpdatedHeader(),
            _headerCard(),
            Expanded(
              child: TabBarView(
                children: [
                  _StatementTab(state: this),
                  _BillsTab(state: this, kind: TaxDocumentKind.invoice),
                  _BillsTab(state: this, kind: TaxDocumentKind.creditNote),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    final color = widget.balanceType == 'Cr' ? _green : _drRed;
    final label = widget.balanceType == 'Cr' ? 'Payable (Cr)' : 'Receivable (Dr)';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (widget.village.isNotEmpty) widget.village,
                    if (widget.phone.isNotEmpty) widget.phone,
                  ].join('  •  '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Text('Net Outstanding',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                Text(
                  widget.balance == 0
                      ? 'Settled'
                      : '${_currency.format(widget.balance)} ${widget.balanceType}',
                  style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w800, color: color),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ],
      ),
    );
  }

  // ---- exports ----------------------------------------------------------

  Future<void> _exportPdf() async {
    if (_statementTxns.isEmpty) return _snack('No transactions to export');
    try {
      final entries = _statementTxns
          .map((t) => LedgerStatementEntry(
                date: t['date'] as DateTime,
                voucherType: t['voucherType'] as String? ?? '',
                voucherNo: t['voucherNo'] as String? ?? '',
                amount: (t['amount'] as num?)?.toDouble() ?? 0.0,
                type: t['type'] as String? ?? 'Dr',
                particulars: t['particulars'] as String? ?? '',
                narration: t['narration'] as String? ?? '',
                runningBalanceSigned: (t['runningBalance'] as num?)?.toDouble(),
              ))
          .toList();
      final bytes = await LedgerStatementPdfService().build(
        title: widget.ledgerName,
        outstandingBalance: widget.balance,
        balanceType: widget.balanceType,
        entries: entries,
      );
      await shareOrDownloadPdf(
        bytes: bytes,
        filename:
            'Statement_${widget.ledgerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf',
      );
    } catch (e) {
      _snack('PDF export failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    if (_statementTxns.isEmpty) return _snack('No transactions to export');
    try {
      await ExcelExportService.exportLedger(
        firmName: widget.ledgerName,
        proprietorName: '',
        phone: widget.phone,
        transactions: _statementTxns,
        outstandingBalance: widget.balance,
        balanceType: widget.balanceType,
      );
    } catch (e) {
      _snack('Excel export failed: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ---------------------------------------------------------------------------
// Statement tab
// ---------------------------------------------------------------------------

class _StatementTab extends StatelessWidget {
  final _PartyLedgerScreenState state;
  const _StatementTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final currency = state._currency;
    return Column(
      children: [
        _exportBar(context),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: state._txnsRef.orderBy('date', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _message(Icons.error_outline_rounded,
                    'Could not load statement', '${snap.error}');
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: _PartyLedgerScreenState._green));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return _message(
                    Icons.receipt_long_outlined,
                    'No transactions yet',
                    'Run the Tally sync to populate this shop\'s statement.');
              }

              final parsed = docs.map((d) {
                final data = d.data();
                return <String, dynamic>{
                  'date': _asDate(data['date']),
                  'voucherType': data['voucherType'] as String? ?? '',
                  'voucherNo': data['voucherNo'] as String? ?? '',
                  'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
                  'type': data['type'] as String? ?? 'Dr',
                  'particulars': data['particulars'] as String? ?? '',
                  'narration': data['narration'] as String? ?? '',
                };
              }).toList();

              // Running balance anchored to the current closing balance.
              final signedClosing =
                  (state.widget.balanceType == 'Cr' ? -1.0 : 1.0) *
                      state.widget.balance;
              double cumulative = 0;
              for (final t in parsed) {
                t['runningBalance'] = signedClosing - cumulative;
                final isDr = (t['type'] as String) != 'Cr';
                cumulative += (isDr ? 1 : -1) * (t['amount'] as double);
              }
              state._statementTxns = parsed;

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: parsed.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _txnCard(ctx, parsed[i], currency),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _exportBar(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: state._exportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('PDF'),
              style: TextButton.styleFrom(
                  foregroundColor: _PartyLedgerScreenState._green),
            ),
            TextButton.icon(
              onPressed: state._exportExcel,
              icon: const Icon(Icons.grid_on_rounded, size: 18),
              label: const Text('Excel'),
              style: TextButton.styleFrom(
                  foregroundColor: _PartyLedgerScreenState._green),
            ),
          ],
        ),
      );

  Widget _txnCard(
      BuildContext context, Map<String, dynamic> t, NumberFormat currency) {
    final isDr = (t['type'] as String) != 'Cr';
    final color = isDr
        ? _PartyLedgerScreenState._drRed
        : _PartyLedgerScreenState._green;
    final running = (t['runningBalance'] as num?)?.toDouble();
    final date = DateFormat('dd MMM yyyy').format(t['date'] as DateTime);
    final particulars = t['particulars'] as String;
    final narration = t['narration'] as String;

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${t['voucherType']}',
                        style: GoogleFonts.outfit(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('$date  •  #${t['voucherNo']}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                    if (running != null)
                      Text(
                        'Bal: ${currency.format(running.abs())} ${running < 0 ? 'Cr' : 'Dr'}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              Text(
                '${currency.format((t['amount'] as num).toDouble())} ${isDr ? 'Dr' : 'Cr'}',
                style: GoogleFonts.outfit(
                    fontSize: 15, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (particulars.isNotEmpty) ...[
                    Text('Particulars',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                            fontWeight: FontWeight.bold)),
                    Text(particulars,
                        style: GoogleFonts.outfit(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                  ],
                  Text('Narration',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold)),
                  Text(narration.isNotEmpty ? narration : '—',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bills tab
// ---------------------------------------------------------------------------

/// Lists one kind of stock document for the party — sales bills, or credit
/// notes (sales returns). Both live in the same `invoices` subcollection tagged
/// with `docType`, so this filters client-side off a single stream rather than
/// needing a second collection and a composite index.
class _BillsTab extends StatelessWidget {
  final _PartyLedgerScreenState state;
  final TaxDocumentKind kind;
  const _BillsTab({required this.state, required this.kind});

  bool _matches(Map<String, dynamic> d) =>
      TaxDocumentKind.fromDocType(d['docType'] as String?) == kind;

  @override
  Widget build(BuildContext context) {
    final currency = state._currency;
    final isCredit = kind == TaxDocumentKind.creditNote;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: state._invoicesRef.orderBy('date', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _message(Icons.error_outline_rounded,
              'Could not load ${isCredit ? 'credit notes' : 'bills'}',
              '${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  CircularProgressIndicator(color: _PartyLedgerScreenState._green));
        }
        final docs = (snap.data?.docs ?? [])
            .map((d) => d.data())
            .where(_matches)
            .toList();
        if (docs.isEmpty) {
          return _message(
              isCredit ? Icons.assignment_return_outlined : Icons.receipt_outlined,
              isCredit ? 'No credit notes yet' : 'No bills yet',
              isCredit
                  ? 'Sales returns for this shop will appear here after the Tally sync.'
                  : 'Sales invoices for this shop will appear here after the Tally sync.');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _billCard(context, docs[i], currency),
        );
      },
    );
  }

  Widget _billCard(
      BuildContext context, Map<String, dynamic> inv, NumberFormat currency) {
    final date = _asDate(inv['date']);
    final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
    final nItems = (inv['items'] as List?)?.length ?? 0;
    final isCredit = kind == TaxDocumentKind.creditNote;
    // Credit notes move money back to the customer, so they read in the same
    // red the Ledger Book uses for a debit balance rather than the sales green.
    final accent = isCredit
        ? _PartyLedgerScreenState._drRed
        : _PartyLedgerScreenState._green;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InvoiceDetailScreen(
          invoice: inv,
          partyName: state.widget.ledgerName,
          partyVillage: state.widget.village,
          partyPhone: state.widget.phone,
          partyGstNo: state.widget.gstNo,
        ),
      )),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                  isCredit
                      ? Icons.assignment_return_rounded
                      : Icons.receipt_long_rounded,
                  color: accent,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${inv['voucherType'] ?? (isCredit ? 'Credit Note' : 'Invoice')}'
                      '  #${inv['voucherNo'] ?? ''}',
                      style: GoogleFonts.outfit(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('dd MMM yyyy').format(date)}  •  $nItems item${nItems == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(currency.format(total),
                    style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isCredit ? accent : const Color(0xFF1B1B1B))),
                const SizedBox(height: 2),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// shared helpers
// ---------------------------------------------------------------------------

DateTime _asDate(dynamic d) {
  if (d is Timestamp) return d.toDate();
  if (d is DateTime) return d;
  if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
  return DateTime.now();
}

Widget _message(IconData icon, String title, String body) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
