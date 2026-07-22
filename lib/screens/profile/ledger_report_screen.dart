import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/services/excel_export_service.dart';
import 'package:shantinath_agro/services/ledger_statement_pdf_service.dart';
import 'package:shantinath_agro/utils/date_range_sheet.dart';
import 'package:printing/printing.dart';

class LedgerReportScreen extends StatefulWidget {
  const LedgerReportScreen({super.key});

  @override
  State<LedgerReportScreen> createState() => _LedgerReportScreenState();
}

class _LedgerReportScreenState extends State<LedgerReportScreen> {
  String _selectedFilter = 'All'; // 'All', 'Sales', 'Receipt', 'Others'
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _lastLoadedTransactions = [];

  Future<void> _pickDateRange() async {
    final isMarathi = context.read<LocaleProvider>().isMarathi;
    final result = await showLedgerDateRangeSheet(context,
        current: _dateRange, isMarathi: isMarathi);
    if (result == null) return;
    setState(() => _dateRange = result.cleared ? null : result.range);
  }

  bool _inDateRange(DateTime date) {
    if (_dateRange == null) return true;
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(
        _dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
    final e = DateTime(
        _dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  Future<void> _exportPdf({
    required String title,
    required double outstandingBalance,
    required String balanceType,
  }) async {
    if (_lastLoadedTransactions.isEmpty) return;
    final entries = _lastLoadedTransactions.map((t) {
      return LedgerStatementEntry(
        date: t['date'] as DateTime,
        voucherType: t['voucherType'] as String? ?? '',
        voucherNo: t['voucherNo']?.toString() ?? '',
        amount: (t['amount'] as num?)?.toDouble() ?? 0.0,
        type: t['type'] as String? ?? 'Dr',
        particulars: t['particulars'] as String? ?? '',
        narration: t['narration'] as String? ?? '',
        runningBalanceSigned: (t['runningBalance'] as num?)?.toDouble(),
      );
    }).toList();

    final bytes = await LedgerStatementPdfService().build(
      title: title,
      outstandingBalance: outstandingBalance,
      balanceType: balanceType,
      entries: entries,
      range: _dateRange,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Statement_${title.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final isMarathi = localeProvider.isMarathi;
    final user = authProvider.currentUser;

    if (user == null) {
      return Scaffold(
        body: Center(
          child: Text(
            isMarathi ? 'कोणताही वापरकर्ता लॉग इन केलेला नाही' : 'No user logged in',
          ),
        ),
      );
    }

    final String title = isMarathi ? 'खाते उतारा (लेजर)' : 'Account Statement (Ledger)';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.phone)
          .collection('private')
          .doc('financials')
          .snapshots(),
      builder: (context, snapshot) {
        double outstandingBalance = 0.0;
        String balanceType = 'Dr';
        DateTime? lastTallySync;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            outstandingBalance = (data['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
            balanceType = data['balanceType'] as String? ?? 'Dr';
            final timestamp = data['lastTallySync'] as Timestamp?;
            if (timestamp != null) {
              lastTallySync = timestamp.toDate();
            }
          }
        }
        final userWithFinancials = user.copyWith(
          outstandingBalance: outstandingBalance,
          balanceType: balanceType,
          lastTallySync: lastTallySync,
        );

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F0),
          appBar: AppBar(
            title: Text(
              title,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
            ),
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: isMarathi ? 'PDF शेअर करा' : 'Share as PDF',
                onPressed: () async {
                  if (_lastLoadedTransactions.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isMarathi
                            ? 'एक्सपोर्ट करण्यासाठी कोणतीही माहिती नाही'
                            : 'No transactions to export'),
                      ),
                    );
                    return;
                  }
                  try {
                    await _exportPdf(
                      title: userWithFinancials.firmName.isNotEmpty
                          ? userWithFinancials.firmName
                          : userWithFinancials.name,
                      outstandingBalance:
                          userWithFinancials.outstandingBalance,
                      balanceType: userWithFinancials.balanceType,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('PDF export failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: isMarathi ? 'एक्सेल मध्ये एक्सपोर्ट करा' : 'Export to Excel',
                onPressed: () async {
                  if (_lastLoadedTransactions.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isMarathi ? 'एक्सपोर्ट करण्यासाठी कोणतीही माहिती नाही' : 'No transactions to export',
                        ),
                      ),
                    );
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMarathi ? 'एक्सेल फाईल तयार करत आहे...' : 'Generating Excel statement...',
                      ),
                    ),
                  );

                  try {
                    await ExcelExportService.exportLedger(
                      firmName: userWithFinancials.firmName.isNotEmpty ? userWithFinancials.firmName : userWithFinancials.name,
                      proprietorName: userWithFinancials.proprietorName,
                      phone: userWithFinancials.phone,
                      transactions: _lastLoadedTransactions,
                      outstandingBalance: userWithFinancials.outstandingBalance,
                      balanceType: userWithFinancials.balanceType,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Export failed: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              // Header summary card
              _buildSummaryCard(context, userWithFinancials, isMarathi),

          // Filters and Search section
          _buildSearchAndFilters(isMarathi),

          // Ledger Transactions List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.phone)
                  .collection('ledger_transactions')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        isMarathi
                            ? 'माहिती लोड करताना त्रुटी आली: ${snapshot.error}'
                            : 'Error loading ledger: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E7D32)),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                
                // Parse and Filter local list
                final parsed = docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  DateTime dateVal = DateTime.now();
                  if (data['date'] != null) {
                    if (data['date'] is Timestamp) {
                      dateVal = (data['date'] as Timestamp).toDate();
                    } else if (data['date'] is String) {
                      dateVal = DateTime.tryParse(data['date'] as String) ?? DateTime.now();
                    }
                  }

                  return {
                    'date': dateVal,
                    'voucherType': data['voucherType'] as String? ?? '',
                    'voucherNo': data['voucherNo'] as String? ?? '',
                    'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
                    'type': data['type'] as String? ?? 'Dr',
                    'particulars': data['particulars'] as String? ?? '',
                    'narration': data['narration'] as String? ?? '',
                  };
                }).toList();

                // Running balance over the FULL timeline (newest first), anchored
                // to the current outstanding balance, so each row shows the true
                // balance at that point even when the list is filtered.
                final double signedClosing =
                    (userWithFinancials.balanceType == 'Cr' ? -1.0 : 1.0) *
                        userWithFinancials.outstandingBalance;
                double cumulative = 0;
                for (final t in parsed) {
                  t['runningBalance'] = signedClosing - cumulative;
                  final isDr = (t['type'] as String? ?? 'Dr') != 'Cr';
                  cumulative += (isDr ? 1 : -1) * (t['amount'] as double);
                }

                final transactions = parsed.where((t) {
                  // Apply date-range filter
                  if (!_inDateRange(t['date'] as DateTime)) return false;

                  // Apply search query
                  final q = _searchQuery.toLowerCase();
                  final narration = t['narration'].toString().toLowerCase();
                  final voucherNo = t['voucherNo'].toString().toLowerCase();
                  final particulars = t['particulars'].toString().toLowerCase();
                  final matchesSearch = q.isEmpty ||
                      narration.contains(q) ||
                      voucherNo.contains(q) ||
                      particulars.contains(q);

                  if (!matchesSearch) return false;

                  // Apply Category Filter
                  final vType = t['voucherType'].toString().toLowerCase();
                  if (_selectedFilter == 'Sales') {
                    return vType.contains('sales') || vType.contains('invoice');
                  } else if (_selectedFilter == 'Receipt') {
                    return vType.contains('receipt') || vType.contains('payment');
                  } else if (_selectedFilter == 'Others') {
                    return !vType.contains('sales') &&
                        !vType.contains('invoice') &&
                        !vType.contains('receipt') &&
                        !vType.contains('payment');
                  }
                  return true;
                }).toList();

                _lastLoadedTransactions = transactions;

                if (transactions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          isMarathi ? 'कोणतेही व्यवहार आढळले नाहीत' : 'No transactions found',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final item = transactions[index];
                    return _buildTransactionCard(item, isMarathi);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildSummaryCard(BuildContext context, var user, bool isMarathi) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
    final String balStr = currencyFormat.format(user.outstandingBalance);
    final String typeText = user.balanceType == 'Dr'
        ? (isMarathi ? 'येणे (Debit)' : 'Debit (Owed)')
        : (isMarathi ? 'जमा (Credit)' : 'Credit (Advance)');
    
    final syncTimeStr = user.lastTallySync != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(user.lastTallySync!)
        : (isMarathi ? 'कधीही नाही' : 'Never');

    final balanceColor = user.balanceType == 'Dr' ? const Color(0xFFC62828) : const Color(0xFF2E7D32);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isMarathi ? 'एकूण थकीत रक्कम' : 'Net Outstanding Balance',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: balanceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  typeText,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: balanceColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            balStr,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: balanceColor,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                isMarathi
                    ? 'टॅली सिंक वेळ: $syncTimeStr'
                    : 'Last Tally Sync: $syncTimeStr',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isMarathi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Search Field
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200, width: 1.2),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2E7D32)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                hintText: isMarathi ? 'शोधा...' : 'Search transactions...',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip('All', isMarathi ? 'सर्व व्यवहार' : 'All Transactions'),
                const SizedBox(width: 8),
                _buildFilterChip('Sales', isMarathi ? 'विक्री बिले' : 'Sales Invoices'),
                const SizedBox(width: 8),
                _buildFilterChip('Receipt', isMarathi ? 'जमा पावती' : 'Receipts'),
                const SizedBox(width: 8),
                _buildFilterChip('Others', isMarathi ? 'इतर' : 'Others'),
                const SizedBox(width: 8),
                _buildDateRangeChip(isMarathi),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDateRangeChip(bool isMarathi) {
    final fmt = DateFormat('dd MMM');
    final hasRange = _dateRange != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionChip(
          avatar: Icon(Icons.date_range_rounded,
              size: 18,
              color:
                  hasRange ? const Color(0xFF2E7D32) : Colors.grey.shade700),
          label: Text(
            hasRange
                ? '${fmt.format(_dateRange!.start)} – ${fmt.format(_dateRange!.end)}'
                : (isMarathi ? 'तारीख निवडा' : 'Date range'),
            style: TextStyle(
              fontSize: 13,
              color:
                  hasRange ? const Color(0xFF2E7D32) : Colors.grey.shade700,
              fontWeight: hasRange ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          onPressed: _pickDateRange,
          backgroundColor: Colors.white,
          side: BorderSide(
              color: hasRange ? const Color(0xFF2E7D32) : Colors.grey.shade300,
              width: 1),
        ),
        if (hasRange)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            color: Colors.grey.shade600,
            onPressed: () => setState(() => _dateRange = null),
            tooltip: isMarathi ? 'तारीख साफ करा' : 'Clear date range',
          ),
      ],
    );
  }

  Widget _buildFilterChip(String filterVal, String displayLabel) {
    final bool isSelected = _selectedFilter == filterVal;
    return ChoiceChip(
      label: Text(
        displayLabel,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : Colors.grey.shade700,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = filterVal;
          });
        }
      },
      selectedColor: const Color(0xFF2E7D32),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
          width: 1,
        ),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> item, bool isMarathi) {
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);
    final String dateStr = DateFormat('dd MMM yyyy').format(item['date'] as DateTime);
    final double amount = item['amount'] as double;
    final String type = item['type'] as String;
    final String vType = item['voucherType'] as String;
    final String vNo = item['voucherNo'] as String;
    final String particulars = item['particulars'] as String;
    final String narration = item['narration'] as String;

    final isDr = type == 'Dr';
    final Color valueColor = isDr ? const Color(0xFFC62828) : const Color(0xFF2E7D32);
    final String indicatorText = isDr ? 'Dr' : 'Cr';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            iconColor: Colors.grey.shade400,
            collapsedIconColor: Colors.grey.shade400,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vType,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: const Color(0xFF212121),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dateStr  •  #$vNo',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item['runningBalance'] != null) ...[
                      const SizedBox(height: 3),
                      Builder(builder: (_) {
                        final running = item['runningBalance'] as double;
                        return Text(
                          '${isMarathi ? 'शिल्लक' : 'Bal'}: '
                          '${currencyFormat.format(running.abs())} '
                          '${running < 0 ? 'Cr' : 'Dr'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
                Row(
                  children: [
                    Text(
                      currencyFormat.format(amount),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: valueColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        indicatorText,
                        style: TextStyle(
                          fontSize: 10,
                          color: valueColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    if (particulars.isNotEmpty) ...[
                      Text(
                        isMarathi ? 'खाते तपशील (Particulars)' : 'Account Particulars',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        particulars,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (narration.isNotEmpty) ...[
                      Text(
                        isMarathi ? 'स्पष्टीकरण (Narration)' : 'Narration / Description',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        narration,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ] else ...[
                      Text(
                        isMarathi ? 'कोणतेही स्पष्टीकरण नाही' : 'No description provided',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
