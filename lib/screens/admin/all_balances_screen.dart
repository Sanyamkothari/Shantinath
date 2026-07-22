import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin "Ledger Book" — shows the outstanding Dr/Cr balance of every customer
/// synced from Tally, regardless of whether they have registered on the app.
///
/// Data source: the `tally_ledgers` collection, populated by the Tally sync
/// agent (tally_sync.py). It is read-only from the app.
class AllBalancesScreen extends StatefulWidget {
  const AllBalancesScreen({super.key});

  @override
  State<AllBalancesScreen> createState() => _AllBalancesScreenState();
}

class _AllBalancesScreenState extends State<AllBalancesScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _drRed = Color(0xFFC62828);

  final _searchController = TextEditingController();
  String _query = '';

  final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          'Ledger Book',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tally_ledgers')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildMessage(
                    Icons.error_outline_rounded,
                    'Could not load balances',
                    '${snapshot.error}',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _green),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _buildMessage(
                    Icons.account_balance_wallet_outlined,
                    'No balance data yet',
                    'Run the Tally sync agent (tally_sync.py) on the shop PC to '
                        'populate customer credit/debit balances here.',
                  );
                }

                // Map + filter.
                final all = docs
                    .map((d) =>
                        _Ledger.fromDoc(d.data() as Map<String, dynamic>))
                    .toList();

                final filtered = _query.isEmpty
                    ? all
                    : all.where((l) {
                        final q = _query.toLowerCase();
                        return l.name.toLowerCase().contains(q) ||
                            l.village.toLowerCase().contains(q) ||
                            l.phone.contains(q);
                      }).toList();

                // Totals across the FULL set (not just the filtered view).
                double totalDr = 0, totalCr = 0;
                for (final l in all) {
                  if (l.balance == 0) continue;
                  if (l.balanceType == 'Cr') {
                    totalCr += l.balance;
                  } else {
                    totalDr += l.balance;
                  }
                }

                return Column(
                  children: [
                    _buildSummary(totalDr, totalCr, all.length),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildMessage(
                              Icons.search_off_rounded,
                              'No matches',
                              'No customer matches "$_query".',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _buildRow(filtered[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: _green,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          hintText: 'Search by name, village or phone',
          prefixIcon: const Icon(Icons.search, color: _green),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(double totalDr, double totalCr, int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryTile('Receivable (Dr)', totalDr, _drRed),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          _summaryTile('Payable (Cr)', totalCr, _green),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          _summaryTile('Customers', count.toDouble(), Colors.black87,
              isCount: true),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, double value, Color color,
      {bool isCount = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            isCount ? value.toInt().toString() : _currency.format(value),
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_Ledger l) {
    final hasBalance = l.balance != 0;
    final color = l.balanceType == 'Cr' ? _green : _drRed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1B1B1B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (l.village.isNotEmpty) l.village,
                    if (l.phone.isNotEmpty) l.phone,
                  ].join('  •  '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hasBalance
                  ? color.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hasBalance
                  ? '${_currency.format(l.balance)} ${l.balanceType}'
                  : 'Settled',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: hasBalance ? color : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single Tally customer balance row.
class _Ledger {
  final String name;
  final String village;
  final String phone;
  final double balance;
  final String balanceType; // 'Dr' or 'Cr'

  const _Ledger({
    required this.name,
    required this.village,
    required this.phone,
    required this.balance,
    required this.balanceType,
  });

  factory _Ledger.fromDoc(Map<String, dynamic> d) {
    return _Ledger(
      name: (d['name'] as String?)?.trim() ?? 'Unknown',
      village: (d['village'] as String?)?.trim() ?? '',
      phone: (d['phone'] as String?)?.trim() ?? '',
      balance: (d['outstandingBalance'] as num?)?.toDouble() ?? 0.0,
      balanceType: (d['balanceType'] as String?) ?? 'Dr',
    );
  }
}
