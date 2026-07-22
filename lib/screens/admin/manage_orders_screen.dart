import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/services/whatsapp_service.dart';
import 'package:shantinath_agro/utils/csv_export_helper.dart';


class ManageOrdersScreen extends StatefulWidget {
  const ManageOrdersScreen({super.key});

  @override
  State<ManageOrdersScreen> createState() => _ManageOrdersScreenState();
}

class _ManageOrdersScreenState extends State<ManageOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<_TabData> _tabs = const [
    _TabData('All', null),
    _TabData('Pending', OrderStatus.pending),
    _TabData('Confirmed', OrderStatus.confirmed),
    _TabData('Delivered', OrderStatus.delivered),
    _TabData('Cancelled', OrderStatus.cancelled),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshOrders() async {
    context.read<OrderProvider>().loadAllOrders();
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _updateStatus(String orderId, OrderStatus newStatus) {
    final currentUser = context.read<AuthProvider>().currentUser;
    context.read<OrderProvider>().updateOrderStatus(
      orderId,
      newStatus,
      lastModifiedById: currentUser?.phone ?? '',
      lastModifiedByName: currentUser?.name ?? '',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Order status updated to ${newStatus.name}'),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  List<Order> _filteredOrders(List<Order> all, OrderStatus? status) {
    List<Order> list;
    if (status == null) {
      list = all;
    } else if (status == OrderStatus.pending) {
      list = all
          .where((o) =>
              o.status == OrderStatus.pending ||
              o.status == OrderStatus.partiallyConfirmed ||
              o.status == OrderStatus.partiallyDelivered)
          .toList();
    } else if (status == OrderStatus.confirmed) {
      list = all
          .where((o) =>
              o.status == OrderStatus.confirmed ||
              o.status == OrderStatus.partiallyConfirmed)
          .toList();
    } else if (status == OrderStatus.delivered) {
      list = all
          .where((o) =>
              o.status == OrderStatus.delivered ||
              o.status == OrderStatus.partiallyDelivered)
          .toList();
    } else {
      list = all.where((o) => o.status == status).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((o) {
        final shortId = o.id.length > 8 ? o.id.substring(o.id.length - 8) : o.id;
        return o.customerName.toLowerCase().contains(q) ||
            o.customerPhone.contains(q) ||
            o.customerVillage.toLowerCase().contains(q) ||
            shortId.toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  Future<void> _exportCurrentTabOrders(List<Order> allOrders) async {
    try {
      final activeTab = _tabs[_tabController.index];
      final filteredList = _filteredOrders(allOrders, activeTab.status);
      
      final headers = ['Order ID', 'Date', 'Customer Name', 'Phone Number', 'Village/City', 'Total Amount', 'Status', 'Notes', 'Item Details'];
      final rows = filteredList.map((o) {
        final itemDetails = o.items.map((item) => '${item.product.name} (Qty: ${item.quantity}, Confirmed: ${item.confirmedQuantity}, Delivered: ${item.deliveredQuantity})').join(' | ');
        return [
          o.id,
          DateFormat('yyyy-MM-dd HH:mm').format(o.createdAt),
          o.customerName,
          o.customerPhone,
          o.customerVillage,
          o.totalAmount,
          o.status.name,
          o.notes,
          itemDetails,
        ];
      }).toList();

      final csv = CsvExportHelper.convertToCsv(headers, rows);
      final statusName = activeTab.label.toLowerCase().replaceAll(' ', '_');
      await CsvExportHelper.exportAndShareCsv(
        fileName: '${statusName}_orders_list_${DateTime.now().millisecondsSinceEpoch}.csv',
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

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.watch<OrderProvider>();
    final allOrders = orderProvider.orders;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          'Manage Orders',
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
            onPressed: () => _exportCurrentTabOrders(allOrders),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w400,
            fontSize: 13,
          ),
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: Column(
        children: [
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
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search orders by name, phone, village...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((tab) {
                return Consumer<OrderProvider>(
                  builder: (context, orderProvider, _) {
                    final orders = _filteredOrders(orderProvider.orders, tab.status);

                    if (orders.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 72,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No ${tab.label.toLowerCase()} orders',
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

                    return RefreshIndicator(
                      onRefresh: _refreshOrders,
                      color: const Color(0xFF2E7D32),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return _OrderCard(
                            order: order,
                            onCallCustomer: () => _callCustomer(order.customerPhone),
                            onUpdateStatus: (status) =>
                                _updateStatus(order.id, status),
                          );
                        },
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab Data helper
// ---------------------------------------------------------------------------
class _TabData {
  final String label;
  final OrderStatus? status;
  const _TabData(this.label, this.status);
}

// ---------------------------------------------------------------------------
// Order Card Widget (Expandable)
// ---------------------------------------------------------------------------
class _OrderCard extends StatefulWidget {
  final Order order;
  final VoidCallback onCallCustomer;
  final Function(OrderStatus) onUpdateStatus;

  const _OrderCard({
    required this.order,
    required this.onCallCustomer,
    required this.onUpdateStatus,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

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
        return const Color(0xFF0288D1); // Blue-grey / Light blue
      case OrderStatus.partiallyDelivered:
        return const Color(0xFF43A047); // Light green
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.schedule_rounded;
      case OrderStatus.confirmed:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.delivered:
        return Icons.local_shipping_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
      case OrderStatus.partiallyConfirmed:
        return Icons.verified_user_outlined;
      case OrderStatus.partiallyDelivered:
        return Icons.local_shipping_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final statusColor = _statusColor(order.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Customer avatar
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _statusIcon(order.status),
                              color: statusColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.customerName,
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF212121),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      dateFormat.format(order.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    if (order.placedByName.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'By ${order.placedByName}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2E7D32),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              order.status.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Summary row
                      Row(
                        children: [
                          _InfoChip(
                            icon: Icons.shopping_bag_outlined,
                            label: '${order.items.length} item${order.items.length != 1 ? 's' : ''}',
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoChip(
                              icon: Icons.location_on_outlined,
                              label: order.customerVillage,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '₹${order.totalAmount.toStringAsFixed(0)}',
                                maxLines: 1,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Expanded content
                if (_expanded) ...[
                  Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  // Order items
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Text(
                      'Order Items',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  ...order.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2E7D32),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (item.confirmedQuantity > 0 ||
                                      item.deliveredQuantity > 0) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (item.deliveredQuantity > 0)
                                          _smallBadge(
                                            'Delivered: ${item.deliveredQuantity}',
                                            const Color(0xFF2E7D32),
                                          ),
                                        if (item.confirmedQuantity > 0)
                                          _smallBadge(
                                            'Confirmed: ${item.confirmedQuantity}',
                                            const Color(0xFF1565C0),
                                          ),
                                        if (item.pendingQuantity > 0)
                                          _smallBadge(
                                            'Pending: ${item.pendingQuantity}',
                                            const Color(0xFFFF8F00),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              'x${item.quantity}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '₹${item.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )),

                  if (order.notes.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.note_rounded,
                              size: 16,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                order.notes,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Action buttons — a Wrap so they flow onto a second line on
                  // narrow screens instead of overflowing the row.
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Call button
                        OutlinedButton.icon(
                          onPressed: widget.onCallCustomer,
                          icon: const Icon(Icons.phone_rounded, size: 18),
                          label: Text(
                            order.customerPhone,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                            side: const BorderSide(color: Color(0xFF2E7D32)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () {
                            try {
                              WhatsAppService.shareOrderToNumber(order, order.customerPhone);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.share_rounded, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.12),
                            foregroundColor: const Color(0xFF25D366),
                          ),
                          tooltip: 'Share on WhatsApp',
                        ),
                        if (order.status != OrderStatus.cancelled &&
                            order.status != OrderStatus.delivered)
                          ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    ProcessQuantitiesDialog(order: order),
                              );
                            },
                            icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                            label: Text(
                              'Confirm/Deliver',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        // Status update
                        PopupMenuButton<OrderStatus>(
                          onSelected: widget.onUpdateStatus,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: Colors.white,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.update_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Update Status',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          itemBuilder: (context) => OrderStatus.values
                              .where((s) => s != order.status)
                              .map((s) => PopupMenuItem(
                                    value: s,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _statusIcon(s),
                                          color: _statusColor(s),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          s.name[0].toUpperCase() +
                                              s.name.substring(1),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: _statusColor(s),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                // Expand indicator
                if (!_expanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info Chip
// ---------------------------------------------------------------------------
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Process Quantities Dialog (Confirm/Deliver Specific Item Quantities)
// ---------------------------------------------------------------------------
class ProcessQuantitiesDialog extends StatefulWidget {
  final Order order;
  const ProcessQuantitiesDialog({super.key, required this.order});

  @override
  State<ProcessQuantitiesDialog> createState() => ProcessQuantitiesDialogState();
}

class ProcessQuantitiesDialogState extends State<ProcessQuantitiesDialog> {
  late List<CartItem> _items;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.order.items.map((item) => item.copyWith()).toList();
  }

  void _save(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final orderProvider = context.read<OrderProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;

    setState(() => _isSaving = true);
    
    final tempOrder = widget.order.copyWith(items: _items);
    final computedStatus = tempOrder.getComputedStatus();

    final success = await orderProvider.updateOrderItemsAndStatus(
      widget.order.id,
      _items,
      computedStatus,
      lastModifiedById: currentUser?.phone ?? '',
      lastModifiedByName: currentUser?.name ?? '',
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Order items and status updated successfully!'),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to update: ${orderProvider.errorMessage ?? "Unknown error"}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        'Confirm / Deliver Items',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(_items.length, (index) {
                final item = _items[index];
                final originalItem = widget.order.items[index];
                
                return Card(
                  elevation: 0,
                  color: const Color(0xFFF5F5F0),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total Ordered: ${item.quantity}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Divider(height: 16),
                        // Confirmed quantity editor
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Confirmed (Pending Delivery):',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: item.confirmedQuantity > 0
                                      ? () {
                                          setState(() {
                                            item.confirmedQuantity--;
                                          });
                                        }
                                      : null,
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${item.confirmedQuantity}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: (item.confirmedQuantity + item.deliveredQuantity) < item.quantity
                                      ? () {
                                          setState(() {
                                            item.confirmedQuantity++;
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Delivered quantity editor
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Delivered:',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  onPressed: item.deliveredQuantity > originalItem.deliveredQuantity
                                      ? () {
                                          setState(() {
                                            item.deliveredQuantity--;
                                          });
                                        }
                                      : null,
                                ),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${item.deliveredQuantity}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  onPressed: (item.confirmedQuantity + item.deliveredQuantity) < item.quantity
                                      ? () {
                                          setState(() {
                                            item.deliveredQuantity++;
                                          });
                                        }
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Remaining Pending:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              '${item.pendingQuantity}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: item.pendingQuantity > 0 ? const Color(0xFFFF8F00) : const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : () => _save(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
