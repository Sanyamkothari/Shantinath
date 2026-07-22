import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only view of current Tally stock levels (from the `tally_stock`
/// collection, populated by the Tally sync). This is a status screen only —
/// it does NOT affect the products catalog, availability, or ordering.
class StockStatusScreen extends StatefulWidget {
  const StockStatusScreen({super.key});

  @override
  State<StockStatusScreen> createState() => _StockStatusScreenState();
}

class _StockStatusScreenState extends State<StockStatusScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _red = Color(0xFFC62828);
  static const Color _amber = Color(0xFFF57F17);

  final _searchController = TextEditingController();
  String _query = '';
  bool _lowStockOnly = false;

  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final _qtyFmt = NumberFormat.decimalPattern('en_IN');

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
        title: Text('Stock Status',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _searchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tally_stock')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _message(Icons.error_outline_rounded,
                      'Could not load stock', '${snapshot.error}');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _green));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _message(
                    Icons.inventory_2_outlined,
                    'No stock data yet',
                    'Run the Tally sync (tally_sync.py) on the shop PC to see '
                        'current stock levels here.',
                  );
                }

                final all = docs
                    .map((d) => _Stock.fromDoc(d.data() as Map<String, dynamic>))
                    .toList();

                // Summary over the FULL set.
                double totalValue = 0;
                int outOfStock = 0;
                for (final s in all) {
                  totalValue += s.value;
                  if (s.quantity <= 0) outOfStock++;
                }

                final filtered = all.where((s) {
                  if (_lowStockOnly && s.quantity > 0) return false;
                  if (_query.isEmpty) return true;
                  final q = _query.toLowerCase();
                  return s.name.toLowerCase().contains(q) ||
                      s.group.toLowerCase().contains(q);
                }).toList();

                return Column(
                  children: [
                    _summary(all.length, totalValue, outOfStock),
                    Expanded(
                      child: filtered.isEmpty
                          ? _message(Icons.search_off_rounded, 'No matches',
                              'No stock item matches your search/filter.')
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: filtered.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _row(filtered[i]),
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

  Widget _searchBar() {
    return Container(
      color: _green,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v.trim()),
        decoration: InputDecoration(
          hintText: 'Search item or group',
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

  Widget _summary(int count, double totalValue, int outOfStock) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _tile('Items', count.toDouble(), Colors.black87, isCount: true),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          _tile('Stock Value', totalValue, _green),
          Container(width: 1, height: 34, color: Colors.grey.shade200),
          GestureDetector(
            onTap: () => setState(() => _lowStockOnly = !_lowStockOnly),
            child: _tile('Out of stock', outOfStock.toDouble(), _red,
                isCount: true, highlight: _lowStockOnly),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, double value, Color color,
      {bool isCount = false, bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: highlight
            ? BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8))
            : null,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                isCount ? value.toInt().toString() : _currency.format(value),
                style: GoogleFonts.outfit(
                    fontSize: 15, fontWeight: FontWeight.w700, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _row(_Stock s) {
    final outOfStock = s.quantity <= 0;
    final low = !outOfStock && s.quantity < 10;
    final qtyColor = outOfStock ? _red : (low ? _amber : _green);

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
                Text(s.name,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (s.group.isNotEmpty) s.group,
                    if (s.value > 0) 'Value: ${_currency.format(s.value)}',
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
              color: qtyColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              outOfStock
                  ? 'Out of stock'
                  : '${_qtyFmt.format(s.quantity)}${s.unit.isNotEmpty ? ' ${s.unit}' : ''}',
              style: GoogleFonts.outfit(
                  fontSize: 13, fontWeight: FontWeight.w700, color: qtyColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _Stock {
  final String name;
  final String group;
  final double quantity;
  final String unit;
  final double value;

  const _Stock({
    required this.name,
    required this.group,
    required this.quantity,
    required this.unit,
    required this.value,
  });

  factory _Stock.fromDoc(Map<String, dynamic> d) {
    return _Stock(
      name: (d['name'] as String?)?.trim() ?? 'Unknown',
      group: (d['group'] as String?)?.trim() ?? '',
      quantity: (d['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: (d['unit'] as String?)?.trim() ?? '',
      value: (d['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
