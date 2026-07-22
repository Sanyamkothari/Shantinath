import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:shantinath_agro/utils/csv_export_helper.dart';

/// Represents an aggregated customer from order data.
class _CustomerInfo {
  final String name;
  final String phone;
  final String village;
  final int orderCount;
  final double totalSpent;
  final List<Order> orders;

  const _CustomerInfo({
    required this.name,
    required this.phone,
    required this.village,
    required this.orderCount,
    required this.totalSpent,
    required this.orders,
  });
}

class CustomerDirectoryScreen extends StatefulWidget {
  const CustomerDirectoryScreen({super.key});

  @override
  State<CustomerDirectoryScreen> createState() =>
      _CustomerDirectoryScreenState();
}

class _CustomerDirectoryScreenState extends State<CustomerDirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> _filterUsers(List<UserModel> users) {
    if (_searchQuery.isEmpty) return users;
    final q = _searchQuery.toLowerCase();
    return users.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.firmName.toLowerCase().contains(q) ||
          u.proprietorName.toLowerCase().contains(q) ||
          u.phone.contains(q) ||
          u.village.toLowerCase().contains(q) ||
          u.taluka.toLowerCase().contains(q) ||
          u.district.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _messageCustomer(String phone) async {
    final cleanPhone = phone.replaceAll('+', '').replaceAll(' ', '').trim();
    final formattedPhone = cleanPhone.startsWith('91') ? cleanPhone : '91$cleanPhone';
    final uri = Uri.parse('https://wa.me/$formattedPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open WhatsApp'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  void _showOrderHistoryForUser(BuildContext context, UserModel user, List<Order> allOrders) {
    final userOrders = allOrders.where((o) => o.customerPhone == user.phone).toList();
    final customerInfo = _CustomerInfo(
      name: user.firmName.isNotEmpty ? user.firmName : user.name,
      phone: user.phone,
      village: user.village,
      orderCount: userOrders.length,
      totalSpent: userOrders.fold<double>(0, (acc, o) => acc + o.totalAmount),
      orders: userOrders,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OrderHistorySheet(customer: customerInfo),
    );
  }

  Future<void> _exportCustomersCsv(List<UserModel> users) async {
    final authProvider = context.read<AuthProvider>();
    final canViewBalances = authProvider.can('viewCustomerBalances');
    try {
      final headers = [
        'Firm Name',
        'Proprietor Name',
        'Phone Number',
        'Village/City',
        'Taluka',
        'District',
        'Outstanding Balance',
        'Balance Type',
        'Approval Status'
      ];
      final rows = <List<dynamic>>[];
      for (final u in users) {
        double balance = 0.0;
        String balanceType = 'Dr';
        if (canViewBalances) {
          final financialsDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(u.phone)
              .collection('private')
              .doc('financials')
              .get();
          if (financialsDoc.exists) {
            final data = financialsDoc.data();
            if (data != null) {
              balance = (data['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
              balanceType = data['balanceType'] as String? ?? 'Dr';
            }
          }
        }
        rows.add([
          u.firmName,
          u.proprietorName,
          u.phone,
          u.village,
          u.taluka,
          u.district,
          balance,
          balanceType,
          u.isApproved ? 'Approved' : 'Pending',
        ]);
      }

      final csv = CsvExportHelper.convertToCsv(headers, rows);
      await CsvExportHelper.exportAndShareCsv(
        fileName: 'customer_directory_${DateTime.now().millisecondsSinceEpoch}.csv',
        csvContent: csv,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  Future<void> _approveCustomer(BuildContext context, UserModel user) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.can('approveUsers')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: You do not have permission to approve registrations.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await authProvider.approveUser(user.phone, true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approved "${user.firmName.isNotEmpty ? user.firmName : user.name}" successfully.'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve customer: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();

    return DefaultTabController(
      length: 2,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final allUsers = docs
              .map((doc) => UserModel.fromJson(doc.data() as Map<String, dynamic>))
              .where((u) => u.role == UserRole.customer) // Customer users only
              .toList();

          final filteredUsers = _filterUsers(allUsers);
          final approvedUsers = filteredUsers.where((u) => u.isApproved).toList();
          final pendingUsers = filteredUsers.where((u) => !u.isApproved).toList();

          return Scaffold(
            backgroundColor: const Color(0xFFF5F5F0),
            appBar: AppBar(
              title: Text(
                'Customer Management',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
              ),
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_rounded),
                  tooltip: 'Export CSV',
                  onPressed: () => _exportCustomersCsv(allUsers),
                ),
                const SizedBox(width: 8),
              ],
              bottom: TabBar(
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Directory'),
                        if (approvedUsers.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${approvedUsers.length}',
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Pending'),
                        if (pendingUsers.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF8F00),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${pendingUsers.length}',
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                // Search bar
                Container(
                  color: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search by name, phone, or village...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Colors.grey.shade500,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: Colors.grey.shade500,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    children: [
                      // Active Directory tab
                      _buildDirectoryList(approvedUsers, orderProvider.orders),
                      // Pending Approvals tab
                      _buildPendingList(pendingUsers),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDirectoryList(List<UserModel> users, List<Order> allOrders) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No active customers found',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final userOrders = allOrders.where((o) => o.customerPhone == user.phone).toList();

        return _CustomerUserCard(
          user: user,
          orderCount: userOrders.length,
          totalSpent: userOrders.fold<double>(0, (acc, o) => acc + o.totalAmount),
          onCall: () => _callCustomer(user.phone),
          onWhatsApp: () => _messageCustomer(user.phone),
          onTap: () => _showOrderHistoryForUser(context, user, allOrders),
        );
      },
    );
  }

  Widget _buildPendingList(List<UserModel> users) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No pending approvals',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'New customer registrations will appear here',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _PendingCustomerCard(
          user: user,
          onCall: () => _callCustomer(user.phone),
          onWhatsApp: () => _messageCustomer(user.phone),
          onApprove: () => _approveCustomer(context, user),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Approved Customer User Card
// ---------------------------------------------------------------------------
class _CustomerUserCard extends StatelessWidget {
  final UserModel user;
  final int orderCount;
  final double totalSpent;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onTap;

  const _CustomerUserCard({
    required this.user,
    required this.orderCount,
    required this.totalSpent,
    required this.onCall,
    required this.onWhatsApp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.firmName.isNotEmpty ? user.firmName : user.name;
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final canViewBalances = authProvider.can('viewCustomerBalances');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF212121),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user.proprietorName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Prop: ${user.proprietorName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              user.village,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$orderCount order${orderCount != 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (canViewBalances)
                            StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.phone)
                                  .collection('private')
                                  .doc('financials')
                                  .snapshots(),
                              builder: (context, snapshot) {
                                double outstandingBalance = 0.0;
                                String balanceType = 'Dr';
                                if (snapshot.hasData && snapshot.data!.exists) {
                                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                                  if (data != null) {
                                    outstandingBalance = (data['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
                                    balanceType = data['balanceType'] as String? ?? 'Dr';
                                  }
                                }
                                final hasBalance = outstandingBalance != 0.0;
                                final balanceColor = balanceType == 'Dr' ? const Color(0xFFC62828) : const Color(0xFF2E7D32);

                                if (hasBalance) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: balanceColor.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${currencyFormat.format(outstandingBalance)} $balanceType',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: balanceColor,
                                      ),
                                    ),
                                  );
                                } else {
                                  return Text(
                                    '₹${totalSpent.toStringAsFixed(0)} total',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }
                              },
                            )
                          else
                            Text(
                              '₹${totalSpent.toStringAsFixed(0)} total',
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
                ),
                // Call & WhatsApp buttons
                Material(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onCall,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.phone_rounded,
                        color: Color(0xFF2E7D32),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: const Color(0xFF25D366).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: onWhatsApp,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.message_rounded,
                        color: Color(0xFF25D366),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending Customer Card Widget
// ---------------------------------------------------------------------------
class _PendingCustomerCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onApprove;

  const _PendingCustomerCard({
    required this.user,
    required this.onCall,
    required this.onWhatsApp,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.firmName.isNotEmpty ? user.firmName : user.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1.5,
        shadowColor: Colors.black12,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8F00).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.lock_clock_rounded,
                        color: Color(0xFFFF8F00),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF212121),
                          ),
                        ),
                        if (user.proprietorName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Proprietor: ${user.proprietorName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Details
              _buildDetailItem(Icons.phone_outlined, user.phone),
              _buildDetailItem(Icons.location_on_outlined, '${user.village}, Tq: ${user.taluka}, Dist: ${user.district}'),
              if (user.gstNo.isNotEmpty) _buildDetailItem(Icons.percent_rounded, 'GST: ${user.gstNo}'),
              if (user.customerType.isNotEmpty)
                _buildDetailItem(
                  Icons.badge_outlined,
                  user.customerType == 'wholesale' ? 'Wholesaler' : 'Retailer',
                ),
              const SizedBox(height: 16),
              // Action Buttons Row
              Row(
                children: [
                  // Call
                  ElevatedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.phone_rounded, size: 16),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                      foregroundColor: const Color(0xFF2E7D32),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // WhatsApp
                  ElevatedButton.icon(
                    onPressed: onWhatsApp,
                    icon: const Icon(Icons.message_rounded, size: 16),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.08),
                      foregroundColor: const Color(0xFF25D366),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const Spacer(),
                  // Approve Button (Green Solid)
                  ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                    label: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Order History Bottom Sheet
// ---------------------------------------------------------------------------
class _OrderHistorySheet extends StatelessWidget {
  final _CustomerInfo customer;

  const _OrderHistorySheet({required this.customer});

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFFFF8F00);
      case OrderStatus.confirmed:
        return const Color(0xFF1565C0);
      case OrderStatus.delivered:
        return const Color(0xFF2E7D32);
      case OrderStatus.cancelled:
        return Colors.red.shade600;
      case OrderStatus.partiallyConfirmed:
        return const Color(0xFF0288D1);
      case OrderStatus.partiallyDelivered:
        return const Color(0xFF43A047);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedOrders = List<Order>.from(customer.orders)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          customer.name.isNotEmpty
                              ? customer.name[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${customer.phone} • ${customer.village}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              // Orders list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: sortedOrders.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildProfileSection(context);
                    }

                    final order = sortedOrders[index - 1];
                    final statusColor = _statusColor(order.status);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Order #${order.id.substring(order.id.length > 6 ? order.id.length - 6 : 0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  order.status.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${order.items.length} items',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '₹${order.totalAmount.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildProfileSection(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: AuthService().getUserByPhone(customer.phone),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32)),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return const SizedBox.shrink(); // No profile found
        }

        final user = snapshot.data!;
        if (user.firmName.isEmpty && user.proprietorName.isEmpty) {
          return const SizedBox.shrink(); // Old user without expanded business profile
        }

        return _CustomerProfileDetailsCard(user: user);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Customer Expandable Profile Details Card
// ---------------------------------------------------------------------------
class _CustomerProfileDetailsCard extends StatefulWidget {
  final UserModel user;

  const _CustomerProfileDetailsCard({required this.user});

  @override
  State<_CustomerProfileDetailsCard> createState() => _CustomerProfileDetailsCardState();
}

class _CustomerProfileDetailsCardState extends State<_CustomerProfileDetailsCard> {
  bool _isExpanded = false;

  Widget _buildRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF212121),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.business_center_rounded, color: Color(0xFF2E7D32), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Business Profile Details',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1B5E20),
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF2E7D32),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.black12),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRow('Firm Name', user.firmName),
                  _buildRow('Proprietor Name', user.proprietorName),
                  _buildRow('Customer Type', user.customerType.isEmpty 
                      ? '' 
                      : (user.customerType == 'wholesale' ? 'Wholesaler' : 'Retailer')),
                  _buildRow('Village / City', user.village),
                  _buildRow('Taluka', user.taluka),
                  _buildRow('District', user.district),
                  _buildRow('GST Number', user.gstNo),
                  _buildRow('Seed License No.', user.seedLicenceNumber),
                  _buildRow('Fertilizer License No.', user.fertilizerLicenceNumber),
                  _buildRow('2nd License No.', user.secondLicenceNumber),
                  _buildRow('Khat ID Number', user.khatIdNo),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
