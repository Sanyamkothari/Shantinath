import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/services/whatsapp_service.dart';
import 'package:shantinath_agro/screens/admin/manage_orders_screen.dart'; // To use ProcessQuantitiesDialog
import 'package:shantinath_agro/utils/csv_export_helper.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/services/sales_report_pdf_service.dart';


class SalesReportsScreen extends StatefulWidget {
  const SalesReportsScreen({super.key});

  @override
  State<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends State<SalesReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Filtering & Sorting State
  String _dateFilter = 'All Time'; // 'All Time', 'Today', 'Last 7 Days', 'Last 30 Days', 'Last 90 Days', 'Custom Range'
  DateTimeRange? _customRange; // used when _dateFilter == 'Custom Range'
  String _statusFilter = 'All Active'; // 'All Active', 'Delivered Only', 'Pending / Partially Pending'
  String _searchQuery = '';
  
  // Simultaneous/Advanced Filters
  String? _selectedCity;
  String? _selectedProductId;
  String? _selectedBrand;
  String? _selectedCategory;

  String _productSort = 'Revenue'; // 'Revenue', 'Quantity', 'Pending', 'Name'
  String _citySort = 'Revenue'; // 'Revenue', 'Orders', 'Name'
  String _customerSort = 'Revenue'; // 'Revenue', 'Quantity', 'Pending', 'Name'

  final TextEditingController _searchController = TextEditingController();
  
  // Track expanded item IDs for lists
  final Set<String> _expandedProductIds = {};
  final Set<String> _expandedCustomerPhones = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  bool _isWithinDateRange(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final orderDate = DateTime(date.year, date.month, date.day);

    if (_dateFilter == 'Today') {
      return orderDate.isAtSameMomentAs(today);
    } else if (_dateFilter == 'Last 7 Days') {
      return date.isAfter(now.subtract(const Duration(days: 7)));
    } else if (_dateFilter == 'Last 30 Days') {
      return date.isAfter(now.subtract(const Duration(days: 30)));
    } else if (_dateFilter == 'Last 90 Days') {
      return date.isAfter(now.subtract(const Duration(days: 90)));
    } else if (_dateFilter == 'Custom Range') {
      if (_customRange == null) return true;
      final start = DateTime(_customRange!.start.year, _customRange!.start.month,
          _customRange!.start.day);
      final end = DateTime(_customRange!.end.year, _customRange!.end.month,
          _customRange!.end.day);
      return !orderDate.isBefore(start) && !orderDate.isAfter(end);
    }
    return true; // All Time
  }

  /// Human-readable description of the active date filter (for chips / PDF).
  String get _dateFilterLabel {
    if (_dateFilter == 'Custom Range' && _customRange != null) {
      final fmt = DateFormat('dd MMM yyyy');
      return '${fmt.format(_customRange!.start)} – ${fmt.format(_customRange!.end)}';
    }
    return _dateFilter;
  }

  bool _matchesStatus(OrderStatus status) {
    if (_statusFilter == 'Delivered Only') {
      return status == OrderStatus.delivered;
    } else if (_statusFilter == 'Pending / Partially Pending') {
      return status == OrderStatus.pending ||
          status == OrderStatus.partiallyConfirmed ||
          status == OrderStatus.partiallyDelivered;
    }
    // All Active (exclude cancelled)
    return status != OrderStatus.cancelled;
  }

  List<Order> _getFilteredOrders(List<Order> allOrders) {
    return allOrders.where((order) {
      // 1. Date range filter
      if (!_isWithinDateRange(order.createdAt)) return false;

      // 2. Status filter
      if (!_matchesStatus(order.status)) return false;

      // 3. City filter (if selected)
      if (_selectedCity != null && _selectedCity!.isNotEmpty) {
        if (order.customerVillage.trim().toLowerCase() != _selectedCity!.toLowerCase()) {
          return false;
        }
      }

      // 4. Product filter (if selected, check if order contains this product)
      if (_selectedProductId != null && _selectedProductId!.isNotEmpty) {
        final containsProduct = order.items.any((item) => item.product.id == _selectedProductId);
        if (!containsProduct) return false;
      }

      // 5. Brand filter (if selected, check if order contains any product of this brand)
      if (_selectedBrand != null && _selectedBrand!.isNotEmpty) {
        final containsBrand = order.items.any((item) => item.product.brand == _selectedBrand);
        if (!containsBrand) return false;
      }

      // 6. Category filter (if selected, check if order contains any product of this category)
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        final containsCategory = order.items.any((item) => item.product.category == _selectedCategory);
        if (!containsCategory) return false;
      }

      return true;
    }).toList();
  }

  List<String> _getUniqueCities(List<Order> orders) {
    final Set<String> cities = {};
    for (final order in orders) {
      final city = order.customerVillage.trim();
      if (city.isNotEmpty) {
        cities.add(city);
      }
    }
    return cities.toList()..sort();
  }

  bool _hasActiveFilters() {
    return _dateFilter != 'All Time' ||
        _statusFilter != 'All Active' ||
        _selectedCity != null ||
        _selectedProductId != null ||
        _selectedBrand != null ||
        _selectedCategory != null;
  }

  void _clearAllFilters() {
    setState(() {
      _dateFilter = 'All Time';
      _customRange = null;
      _statusFilter = 'All Active';
      _selectedCity = null;
      _selectedProductId = null;
      _selectedBrand = null;
      _selectedCategory = null;
    });
  }

  void _showExportOptions(BuildContext context, List<Order> filteredOrders, List<Order> allOrders) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Export Report',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFC62828)),
              title: const Text('Sales Report PDF'),
              subtitle: Text('Summary + top products, customers & cities · $_dateFilterLabel'),
              onTap: () {
                Navigator.pop(ctx);
                _exportSalesPdf(filteredOrders);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.table_chart_rounded, color: Color(0xFF2E7D32)),
              title: const Text('Export Current Tab Data (CSV)'),
              subtitle: Text(
                _tabController.index == 0
                    ? 'Product-wise sales summary'
                    : _tabController.index == 1
                        ? 'City-wise sales summary'
                        : 'Customer-wise sales summary',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportCurrentTab(filteredOrders, allOrders);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.receipt_long_rounded, color: Color(0xFF1565C0)),
              title: const Text('Export Detailed Orders List'),
              subtitle: Text('${filteredOrders.length} orders matching filters'),
              onTap: () {
                Navigator.pop(ctx);
                _exportDetailedOrders(filteredOrders);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Aggregates the filtered orders and shares a summary Sales Report PDF.
  Future<void> _exportSalesPdf(List<Order> filteredOrders) async {
    bool passesSub(Product p) {
      if (_selectedProductId != null &&
          _selectedProductId!.isNotEmpty &&
          p.id != _selectedProductId) {
        return false;
      }
      if (_selectedBrand != null &&
          _selectedBrand!.isNotEmpty &&
          p.brand != _selectedBrand) {
        return false;
      }
      if (_selectedCategory != null &&
          _selectedCategory!.isNotEmpty &&
          p.category != _selectedCategory) {
        return false;
      }
      return true;
    }

    final Map<String, _ProductSalesData> productMap = {};
    final Map<String, _CustomerSalesData> customerMap = {};
    final Map<String, _CitySalesData> cityMap = {};
    double totalRevenue = 0;
    int totalUnits = 0;
    int contributingOrders = 0;

    for (final order in filteredOrders) {
      final city = order.customerVillage.trim().isEmpty
          ? 'Unknown'
          : order.customerVillage.trim();
      double orderRevenue = 0;
      int orderUnits = 0;

      for (final item in order.items) {
        if (!passesSub(item.product)) continue;
        orderRevenue += item.totalPrice;
        orderUnits += item.quantity;

        final pd = productMap.putIfAbsent(
            item.product.id, () => _ProductSalesData(item.product));
        pd.totalSold += item.quantity;
        pd.totalRevenue += item.totalPrice;

        final cd = cityMap.putIfAbsent(city, () => _CitySalesData(city));
        cd.totalUnitsSold += item.quantity;
        cd.totalRevenue += item.totalPrice;
        cd.customerPhones.add(order.customerPhone);
        cd.productQuantities.update(
            item.product.name, (v) => v + item.quantity,
            ifAbsent: () => item.quantity);
      }

      if (orderUnits == 0) continue; // sub-filters excluded this order
      contributingOrders++;
      totalRevenue += orderRevenue;
      totalUnits += orderUnits;

      cityMap[city]!.orderCount += 1;

      final cust = customerMap.putIfAbsent(
        order.customerPhone,
        () => _CustomerSalesData(
            name: order.customerName,
            phone: order.customerPhone,
            village: city),
      );
      cust.totalUnitsPurchased += orderUnits;
      cust.totalRevenueSpent += orderRevenue;
    }

    final cur =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final products = productMap.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    final customers = customerMap.values.toList()
      ..sort((a, b) => b.totalRevenueSpent.compareTo(a.totalRevenueSpent));
    final cities = cityMap.values.toList()
      ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final productRows = products
        .take(15)
        .map((p) =>
            [p.product.name, '${p.totalSold}', cur.format(p.totalRevenue)])
        .toList();
    final customerRows = customers
        .take(15)
        .map((c) => [c.name, c.village, cur.format(c.totalRevenueSpent)])
        .toList();
    final cityRows = cities
        .take(15)
        .map((c) => [c.cityName, '${c.orderCount}', cur.format(c.totalRevenue)])
        .toList();

    try {
      final service = SalesReportPdfService();
      final bytes = await service.build(
        sellerName: AppConstants.sellerName,
        period: _dateFilterLabel,
        totalRevenue: totalRevenue,
        totalUnits: totalUnits,
        cityCount: cityMap.length,
        orderCount: contributingOrders,
        productRows: productRows,
        customerRows: customerRows,
        cityRows: cityRows,
      );
      await service.shareBytes(bytes,
          'Sales_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportCurrentTab(List<Order> filteredOrders, List<Order> allOrders) async {
    try {
      if (_tabController.index == 0) {
        // Product-wise
        final Map<String, _ProductSalesData> productMap = {};
        for (final order in filteredOrders) {
          for (final item in order.items) {
            final prod = item.product;
            if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
              continue;
            }
            if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
              continue;
            }
            if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
              continue;
            }
            productMap.putIfAbsent(prod.id, () => _ProductSalesData(prod));
            final salesData = productMap[prod.id]!;
            salesData.totalSold += item.quantity;
            salesData.totalRevenue += item.totalPrice;
          }
        }
        for (final order in allOrders) {
          if (order.status == OrderStatus.cancelled) continue;
          if (_selectedCity != null && _selectedCity!.isNotEmpty) {
            if (order.customerVillage.trim().toLowerCase() != _selectedCity!.toLowerCase()) {
              continue;
            }
          }
          for (final item in order.items) {
            if (item.pendingQuantity > 0) {
              final prod = item.product;
              if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
                continue;
              }
              if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
                continue;
              }
              if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
                continue;
              }
              productMap.putIfAbsent(prod.id, () => _ProductSalesData(prod));
              final salesData = productMap[prod.id]!;
              salesData.pendingQty += item.pendingQuantity;
            }
          }
        }
        List<_ProductSalesData> list = productMap.values.toList();
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          list = list.where((p) =>
              p.product.name.toLowerCase().contains(q) ||
              p.product.brand.toLowerCase().contains(q)).toList();
        }
        if (_productSort == 'Quantity') {
          list.sort((a, b) => b.totalSold.compareTo(a.totalSold));
        } else if (_productSort == 'Pending') {
          list.sort((a, b) => b.pendingQty.compareTo(a.pendingQty));
        } else if (_productSort == 'Name') {
          list.sort((a, b) => a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()));
        } else {
          list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
        }

        final headers = ['Product ID', 'Product Name', 'Brand', 'Category', 'Crop Type', 'Pack Size', 'Unit Price', 'Total Qty Sold', 'Pending Qty', 'Total Revenue'];
        final rows = list.map((p) => [
          p.product.id,
          p.product.name,
          p.product.brand,
          p.product.category,
          p.product.cropType,
          p.product.packSize,
          p.product.price,
          p.totalSold,
          p.pendingQty,
          p.totalRevenue,
        ]).toList();

        final csv = CsvExportHelper.convertToCsv(headers, rows);
        await CsvExportHelper.exportAndShareCsv(
          fileName: 'product_wise_sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
          csvContent: csv,
        );
      } else if (_tabController.index == 1) {
        // City-wise
        final Map<String, _CitySalesData> cityMap = {};
        for (final order in filteredOrders) {
          final rawCity = order.customerVillage.trim();
          if (rawCity.isEmpty) continue;
          final key = rawCity.toLowerCase();
          int cityItemsSold = 0;
          double cityRevenueSold = 0.0;
          final Map<String, int> orderProductQuantities = {};
          for (final item in order.items) {
            final prod = item.product;
            if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
              continue;
            }
            if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
              continue;
            }
            if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
              continue;
            }
            cityItemsSold += item.quantity;
            cityRevenueSold += item.totalPrice;
            orderProductQuantities[prod.name] = (orderProductQuantities[prod.name] ?? 0) + item.quantity;
          }
          if (cityItemsSold > 0) {
            cityMap.putIfAbsent(key, () => _CitySalesData(rawCity));
            final cityData = cityMap[key]!;
            cityData.orderCount++;
            cityData.totalUnitsSold += cityItemsSold;
            cityData.totalRevenue += cityRevenueSold;
            cityData.customerPhones.add(order.customerPhone);
            orderProductQuantities.forEach((prodName, qty) {
              cityData.productQuantities[prodName] = (cityData.productQuantities[prodName] ?? 0) + qty;
            });
          }
        }
        List<_CitySalesData> list = cityMap.values.toList();
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          list = list.where((c) => c.cityName.toLowerCase().contains(q)).toList();
        }
        if (_citySort == 'Orders') {
          list.sort((a, b) => b.orderCount.compareTo(a.orderCount));
        } else if (_citySort == 'Name') {
          list.sort((a, b) => a.cityName.toLowerCase().compareTo(b.cityName.toLowerCase()));
        } else {
          list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
        }

        final headers = ['City Name', 'Total Orders', 'Total Units Sold', 'Total Revenue', 'Unique Customers', 'Top Product'];
        final rows = list.map((c) => [
          c.cityName,
          c.orderCount,
          c.totalUnitsSold,
          c.totalRevenue,
          c.customerPhones.length,
          c.topProduct,
        ]).toList();

        final csv = CsvExportHelper.convertToCsv(headers, rows);
        await CsvExportHelper.exportAndShareCsv(
          fileName: 'city_wise_sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
          csvContent: csv,
        );
      } else {
        // Customer-wise
        final Map<String, _CustomerSalesData> customerMap = {};
        for (final order in filteredOrders) {
          final key = order.customerPhone;
          int customerUnits = 0;
          double customerRevenue = 0.0;
          for (final item in order.items) {
            final prod = item.product;
            if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
              continue;
            }
            if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
              continue;
            }
            if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
              continue;
            }
            customerUnits += item.quantity;
            customerRevenue += item.totalPrice;
          }
          if (customerUnits > 0) {
            customerMap.putIfAbsent(key, () => _CustomerSalesData(name: order.customerName, phone: order.customerPhone, village: order.customerVillage));
            final data = customerMap[key]!;
            data.totalUnitsPurchased += customerUnits;
            data.totalRevenueSpent += customerRevenue;
          }
        }
        for (final order in allOrders) {
          if (order.status == OrderStatus.cancelled) continue;
          if (_selectedCity != null && _selectedCity!.isNotEmpty) {
            if (order.customerVillage.trim().toLowerCase() != _selectedCity!.toLowerCase()) {
              continue;
            }
          }
          final key = order.customerPhone;
          int orderPending = 0;
          for (final item in order.items) {
            if (item.pendingQuantity > 0) {
              final prod = item.product;
              if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
                continue;
              }
              if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
                continue;
              }
              if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
                continue;
              }
              orderPending += item.pendingQuantity;
            }
          }
          if (orderPending > 0) {
            customerMap.putIfAbsent(key, () => _CustomerSalesData(name: order.customerName, phone: order.customerPhone, village: order.customerVillage));
            final data = customerMap[key]!;
            data.pendingQty += orderPending;
          }
        }
        List<_CustomerSalesData> list = customerMap.values.toList();
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          list = list.where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.contains(q) ||
              c.village.toLowerCase().contains(q)).toList();
        }
        if (_customerSort == 'Quantity') {
          list.sort((a, b) => b.totalUnitsPurchased.compareTo(a.totalUnitsPurchased));
        } else if (_customerSort == 'Pending') {
          list.sort((a, b) => b.pendingQty.compareTo(a.pendingQty));
        } else if (_customerSort == 'Name') {
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        } else {
          list.sort((a, b) => b.totalRevenueSpent.compareTo(a.totalRevenueSpent));
        }

        final headers = ['Customer Name', 'Phone Number', 'Village/City', 'Total Units Purchased', 'Pending Units', 'Total Spending'];
        final rows = list.map((c) => [
          c.name,
          c.phone,
          c.village,
          c.totalUnitsPurchased,
          c.pendingQty,
          c.totalRevenueSpent,
        ]).toList();

        final csv = CsvExportHelper.convertToCsv(headers, rows);
        await CsvExportHelper.exportAndShareCsv(
          fileName: 'customer_wise_sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
          csvContent: csv,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export CSV: $e')),
        );
      }
    }
  }

  Future<void> _exportDetailedOrders(List<Order> filteredOrders) async {
    try {
      final headers = ['Order ID', 'Date', 'Customer Name', 'Phone Number', 'Village/City', 'Total Amount', 'Status', 'Notes', 'Item Details'];
      final rows = filteredOrders.map((o) {
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
      await CsvExportHelper.exportAndShareCsv(
        fileName: 'filtered_orders_list_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
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
    final productProvider = context.watch<ProductProvider>();
    
    final allOrders = orderProvider.orders;
    final filteredOrders = _getFilteredOrders(allOrders);

    // Calculate Summary Stats
    double totalRevenue = 0.0;
    int totalItemsSold = 0;
    final Set<String> activeVillages = {};

    for (final order in filteredOrders) {
      double orderFilteredRevenue = 0.0;
      int orderFilteredItems = 0;

      for (final item in order.items) {
        final prod = item.product;
        if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
          continue;
        }
        if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
          continue;
        }
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
          continue;
        }
        orderFilteredItems += item.quantity;
        orderFilteredRevenue += item.totalPrice;
      }

      if (orderFilteredItems > 0) {
        totalRevenue += orderFilteredRevenue;
        totalItemsSold += orderFilteredItems;
        if (order.customerVillage.trim().isNotEmpty) {
          activeVillages.add(order.customerVillage.trim().toLowerCase());
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          'Sales Reports',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF2E7D32), // Primary Green
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Export CSV',
            onPressed: () => _showExportOptions(context, filteredOrders, allOrders),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
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
          tabs: const [
            Tab(text: 'Product-wise Sales'),
            Tab(text: 'City/Village-wise'),
            Tab(text: 'Customer-wise'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar & Filter trigger button container
          Container(
            color: const Color(0xFF2E7D32),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
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
                        hintText: 'Search by name, brand, city or customer...',
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
                const SizedBox(width: 10),
                // Filter Bottom Sheet Trigger Button
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 1,
                  shadowColor: Colors.black12,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openFilterBottomSheet(context, productProvider, allOrders),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.filter_list_rounded,
                        color: _hasActiveFilters() ? const Color(0xFF2E7D32) : Colors.grey.shade600,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Active Filter Chips (if any filters applied)
          if (_hasActiveFilters()) _buildActiveFilterChips(productProvider),

          // Summary Stats Cards (Revenue included)
          _buildSummaryStats(totalRevenue, totalItemsSold, activeVillages.length),

          // Main Tabs Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProductWiseTab(filteredOrders, allOrders),
                _buildCityWiseTab(filteredOrders),
                _buildCustomerWiseTab(filteredOrders, allOrders),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Active Filter Chips Row
  // ---------------------------------------------------------------------------
  Widget _buildActiveFilterChips(ProductProvider productProvider) {
    final List<Widget> chips = [];

    if (_dateFilter != 'All Time') {
      chips.add(_buildFilterChip('Date: $_dateFilterLabel', () => setState(() {
            _dateFilter = 'All Time';
            _customRange = null;
          })));
    }
    if (_statusFilter != 'All Active') {
      chips.add(_buildFilterChip('Status: $_statusFilter', () => setState(() => _statusFilter = 'All Active')));
    }
    if (_selectedCategory != null) {
      chips.add(_buildFilterChip('Category: $_selectedCategory', () => setState(() => _selectedCategory = null)));
    }
    if (_selectedBrand != null) {
      chips.add(_buildFilterChip('Brand: $_selectedBrand', () => setState(() => _selectedBrand = null)));
    }
    if (_selectedProductId != null) {
      final pName = productProvider.adminProducts.firstWhere((p) => p.id == _selectedProductId, orElse: () => Product(id: '', name: 'Product', nameMr: '', brand: '', category: '', cropType: '', packSize: '', price: 0, imageUrl: '', description: '', descriptionMr: '', createdAt: DateTime.now())).name;
      chips.add(_buildFilterChip('Product: $pName', () => setState(() => _selectedProductId = null)));
    }
    if (_selectedCity != null) {
      chips.add(_buildFilterChip('City: $_selectedCity', () => setState(() => _selectedCity = null)));
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            ...chips,
            const SizedBox(width: 8),
            TextButton(
              onPressed: _clearAllFilters,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Clear All',
                style: GoogleFonts.outfit(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, VoidCallback onClear) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        onDeleted: onClear,
        deleteIcon: const Icon(Icons.close_rounded, size: 14),
        deleteIconColor: const Color(0xFF2E7D32),
        backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        side: BorderSide(color: const Color(0xFF2E7D32).withValues(alpha: 0.15), width: 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Summary Statistics Cards
  // ---------------------------------------------------------------------------
  Widget _buildSummaryStats(double revenue, int itemsCount, int citiesCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _buildStatSummaryCard(
            label: 'Total Revenue',
            value: '₹${revenue.toStringAsFixed(0)}',
            color: const Color(0xFF2E7D32), // Primary Green
            icon: Icons.currency_rupee_rounded,
          ),
          const SizedBox(width: 10),
          _buildStatSummaryCard(
            label: 'Units Sold',
            value: '$itemsCount',
            color: const Color(0xFF1565C0), // Blue
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: 10),
          _buildStatSummaryCard(
            label: 'Active Cities',
            value: '$citiesCount',
            color: const Color(0xFFE65100), // Orange
            icon: Icons.location_on_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStatSummaryCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF212121),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Product-wise Sales
  // ---------------------------------------------------------------------------
  Widget _buildProductWiseTab(List<Order> filteredOrders, List<Order> allOrders) {
    // Map productId -> ProductSalesData
    final Map<String, _ProductSalesData> productMap = {};

    // 1. First aggregate sales from the filteredOrders
    for (final order in filteredOrders) {
      for (final item in order.items) {
        final prod = item.product;
        
        // Item-level filters
        if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
          continue;
        }
        if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
          continue;
        }
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
          continue;
        }

        productMap.putIfAbsent(prod.id, () => _ProductSalesData(prod));
        
        final salesData = productMap[prod.id]!;
        salesData.totalSold += item.quantity;
        salesData.totalRevenue += item.totalPrice;
      }
    }

    // 2. Next, calculate pending counts from ALL orders
    for (final order in allOrders) {
      if (order.status == OrderStatus.cancelled) continue;
      
      // City-level filter applied to pending orders
      if (_selectedCity != null && _selectedCity!.isNotEmpty) {
        if (order.customerVillage.trim().toLowerCase() != _selectedCity!.toLowerCase()) {
          continue;
        }
      }

      for (final item in order.items) {
        if (item.pendingQuantity > 0) {
          final prod = item.product;
          
          if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
            continue;
          }
          if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
            continue;
          }
          if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
            continue;
          }

          productMap.putIfAbsent(prod.id, () => _ProductSalesData(prod));
          
          final salesData = productMap[prod.id]!;
          salesData.pendingQty += item.pendingQuantity;
          if (!salesData.pendingOrders.contains(order)) {
            salesData.pendingOrders.add(order);
          }
        }
      }
    }

    // Convert map to list and filter by search query
    List<_ProductSalesData> list = productMap.values.toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) =>
          p.product.name.toLowerCase().contains(q) ||
          p.product.brand.toLowerCase().contains(q)).toList();
    }

    // Sort the list
    if (_productSort == 'Quantity') {
      list.sort((a, b) => b.totalSold.compareTo(a.totalSold));
    } else if (_productSort == 'Pending') {
      list.sort((a, b) => b.pendingQty.compareTo(a.pendingQty));
    } else if (_productSort == 'Name') {
      list.sort((a, b) => a.product.name.toLowerCase().compareTo(b.product.name.toLowerCase()));
    } else {
      // Default: Revenue
      list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    }

    if (list.isEmpty) {
      return _buildEmptyState('No products matched filters or search');
    }

    return Column(
      children: [
        // Sort Actions row
        _buildSortRow(
          options: ['Revenue', 'Quantity', 'Pending', 'Name'],
          current: _productSort,
          onSelect: (val) => setState(() => _productSort = val),
        ),
        
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final isExpanded = _expandedProductIds.contains(item.product.id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  shadowColor: Colors.black12,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedProductIds.remove(item.product.id);
                        } else {
                          _expandedProductIds.add(item.product.id);
                        }
                      });
                    },
                    child: Column(
                      children: [
                        // Product Main Card Info
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Product Image / Category Icon
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: item.product.imageUrl.isNotEmpty
                                      ? Image.network(
                                          item.product.imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Icon(Icons.grass_rounded, color: Color(0xFF2E7D32)),
                                        )
                                      : const Icon(Icons.grass_rounded, color: Color(0xFF2E7D32), size: 24),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.product.name,
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: const Color(0xFF212121),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Brand: ${item.product.brand}  |  ${item.product.packSize}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Text(
                                          'Sold: ${item.totalSold}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'Revenue: ₹${item.totalRevenue.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                              // Pending Badge & Expand Arrow
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (item.pendingQty > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'PENDING: ${item.pendingQty}',
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFFF8F00),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    color: Colors.grey.shade400,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Expanded Pending Customers Section
                        if (isExpanded) ...[
                          Divider(height: 1, color: Colors.grey.shade200),
                          Container(
                            color: const Color(0xFFFCFCFB),
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Customer Orders',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (item.pendingOrders.isEmpty)
                                  const Text(
                                    'No pending orders for this product.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                  )
                                else
                                  ...item.pendingOrders.map((order) {
                                    // Find the specific item to get its pendingQty
                                    final cartItem = order.items.firstWhere(
                                      (i) => i.product.id == item.product.id,
                                      orElse: () => CartItem(product: item.product, quantity: 0),
                                    );

                                    if (cartItem.pendingQuantity <= 0) return const SizedBox.shrink();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F5F0),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          // Customer details
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  order.customerName,
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Village: ${order.customerVillage}  |  Phone: ${order.customerPhone}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  'Ordered Date: ${DateFormat('dd MMM, yyyy  hh:mm a').format(order.createdAt)}',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Pending qty & Actions
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Pending: ${cartItem.pendingQuantity}',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(0xFFFF8F00),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  // Call button
                                                  InkWell(
                                                    onTap: () => _callCustomer(order.customerPhone),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF2E7D32)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // WhatsApp button
                                                  InkWell(
                                                    onTap: () {
                                                      try {
                                                        WhatsAppService.shareOrderToNumber(order, order.customerPhone);
                                                      } catch (e) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
                                                        );
                                                      }
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.share_rounded, size: 16, color: Color(0xFF25D366)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Fulfill Button
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => ProcessQuantitiesDialog(order: order),
                                                      );
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF1565C0),
                                                      foregroundColor: Colors.white,
                                                      elevation: 0,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    child: Text(
                                                      'Fulfill',
                                                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: City-wise Sales
  // ---------------------------------------------------------------------------
  Widget _buildCityWiseTab(List<Order> filteredOrders) {
    // Map city/village -> CitySalesData
    final Map<String, _CitySalesData> cityMap = {};

    for (final order in filteredOrders) {
      final rawCity = order.customerVillage.trim();
      if (rawCity.isEmpty) continue;

      final key = rawCity.toLowerCase();
      
      // Calculate item quantities and revenue contribution under active filters
      int cityItemsSold = 0;
      double cityRevenueSold = 0.0;
      final Map<String, int> orderProductQuantities = {};

      for (final item in order.items) {
        final prod = item.product;

        if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
          continue;
        }
        if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
          continue;
        }
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
          continue;
        }

        cityItemsSold += item.quantity;
        cityRevenueSold += item.totalPrice;
        orderProductQuantities[prod.name] = (orderProductQuantities[prod.name] ?? 0) + item.quantity;
      }

      // If this order contains items matching filters, aggregate them
      if (cityItemsSold > 0) {
        cityMap.putIfAbsent(key, () => _CitySalesData(rawCity));
        final cityData = cityMap[key]!;
        cityData.orderCount++;
        cityData.totalUnitsSold += cityItemsSold;
        cityData.totalRevenue += cityRevenueSold;
        cityData.customerPhones.add(order.customerPhone);

        orderProductQuantities.forEach((prodName, qty) {
          cityData.productQuantities[prodName] = (cityData.productQuantities[prodName] ?? 0) + qty;
        });
      }
    }

    // Convert map to list and filter by search query
    List<_CitySalesData> list = cityMap.values.toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) => c.cityName.toLowerCase().contains(q)).toList();
    }

    // Sort the list
    if (_citySort == 'Orders') {
      list.sort((a, b) => b.orderCount.compareTo(a.orderCount));
    } else if (_citySort == 'Name') {
      list.sort((a, b) => a.cityName.toLowerCase().compareTo(b.cityName.toLowerCase()));
    } else {
      // Default: Revenue
      list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
    }

    if (list.isEmpty) {
      return _buildEmptyState('No cities matched filters or search');
    }

    return Column(
      children: [
        // Sort Actions row
        _buildSortRow(
          options: ['Revenue', 'Orders', 'Name'],
          current: _citySort,
          onSelect: (val) => setState(() => _citySort = val),
        ),
        
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  shadowColor: Colors.black12,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Location Pin Icon
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
                          child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        // City sales info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.cityName,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: const Color(0xFF212121),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Orders: ${item.orderCount}  |  Customers: ${item.customerPhones.length}  |  Qty: ${item.totalUnitsSold}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 6),
                              RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  children: [
                                    const TextSpan(text: 'Top Product: '),
                                    TextSpan(
                                      text: item.topProduct,
                                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Revenue info column on the right
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${item.totalRevenue.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Revenue',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Customer-wise Sales
  // ---------------------------------------------------------------------------
  Widget _buildCustomerWiseTab(List<Order> filteredOrders, List<Order> allOrders) {
    // Map customerPhone -> CustomerSalesData
    final Map<String, _CustomerSalesData> customerMap = {};

    // 1. Aggregate sales stats from filteredOrders
    for (final order in filteredOrders) {
      final key = order.customerPhone;
      
      int customerUnits = 0;
      double customerRevenue = 0.0;

      for (final item in order.items) {
        final prod = item.product;

        if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
          continue;
        }
        if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
          continue;
        }
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
          continue;
        }

        customerUnits += item.quantity;
        customerRevenue += item.totalPrice;
      }

      if (customerUnits > 0) {
        customerMap.putIfAbsent(
          key,
          () => _CustomerSalesData(
            name: order.customerName,
            phone: order.customerPhone,
            village: order.customerVillage,
          ),
        );
        final data = customerMap[key]!;
        data.totalUnitsPurchased += customerUnits;
        data.totalRevenueSpent += customerRevenue;
      }
    }

    // 2. Aggregate pending counts from ALL orders
    for (final order in allOrders) {
      if (order.status == OrderStatus.cancelled) continue;

      // City-level filter applied to pending orders
      if (_selectedCity != null && _selectedCity!.isNotEmpty) {
        if (order.customerVillage.trim().toLowerCase() != _selectedCity!.toLowerCase()) {
          continue;
        }
      }

      final key = order.customerPhone;
      int orderPending = 0;

      for (final item in order.items) {
        if (item.pendingQuantity > 0) {
          final prod = item.product;

          if (_selectedProductId != null && _selectedProductId!.isNotEmpty && prod.id != _selectedProductId) {
            continue;
          }
          if (_selectedBrand != null && _selectedBrand!.isNotEmpty && prod.brand != _selectedBrand) {
            continue;
          }
          if (_selectedCategory != null && _selectedCategory!.isNotEmpty && prod.category != _selectedCategory) {
            continue;
          }

          orderPending += item.pendingQuantity;
        }
      }

      if (orderPending > 0) {
        customerMap.putIfAbsent(
          key,
          () => _CustomerSalesData(
            name: order.customerName,
            phone: order.customerPhone,
            village: order.customerVillage,
          ),
        );
        final data = customerMap[key]!;
        data.pendingQty += orderPending;
        if (!data.pendingOrders.contains(order)) {
          data.pendingOrders.add(order);
        }
      }
    }

    // Convert map to list and filter by search query
    List<_CustomerSalesData> list = customerMap.values.toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((c) =>
          c.name.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.village.toLowerCase().contains(q)).toList();
    }

    // Sort the list
    if (_customerSort == 'Quantity') {
      list.sort((a, b) => b.totalUnitsPurchased.compareTo(a.totalUnitsPurchased));
    } else if (_customerSort == 'Pending') {
      list.sort((a, b) => b.pendingQty.compareTo(a.pendingQty));
    } else if (_customerSort == 'Name') {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else {
      // Default: Revenue
      list.sort((a, b) => b.totalRevenueSpent.compareTo(a.totalRevenueSpent));
    }

    if (list.isEmpty) {
      return _buildEmptyState('No customers matched filters or search');
    }

    return Column(
      children: [
        // Sort Actions row
        _buildSortRow(
          options: ['Revenue', 'Quantity', 'Pending', 'Name'],
          current: _customerSort,
          onSelect: (val) => setState(() => _customerSort = val),
        ),
        
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final customer = list[index];
              final isExpanded = _expandedCustomerPhones.contains(customer.phone);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 1,
                  shadowColor: Colors.black12,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedCustomerPhones.remove(customer.phone);
                        } else {
                          _expandedCustomerPhones.add(customer.phone);
                        }
                      });
                    },
                    child: Column(
                      children: [
                        // Customer Main Card Info
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // Avatar / Initials container matching Customer Directory
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
                                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
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
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF212121),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade500),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            customer.village,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Units Purchased: ${customer.totalUnitsPurchased}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Spent Revenue & Pending Badge
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '₹${customer.totalRevenueSpent.toStringAsFixed(0)}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Spent',
                                    style: TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                  if (customer.pendingQty > 0) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF8F00).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'PENDING: ${customer.pendingQty}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                color: Colors.grey.shade400,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                        
                        // Expanded Customer Pending Orders Section
                        if (isExpanded) ...[
                          Divider(height: 1, color: Colors.grey.shade200),
                          Container(
                            color: const Color(0xFFFCFCFB),
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pending Orders Breakdown',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (customer.pendingOrders.isEmpty)
                                  const Text(
                                    'No pending orders for this customer.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                                  )
                                else
                                  ...customer.pendingOrders.map((order) {
                                    final pendingItems = order.items.where((i) => i.pendingQuantity > 0).toList();
                                    if (pendingItems.isEmpty) return const SizedBox.shrink();

                                    final shortId = order.id.length > 8 ? order.id.substring(order.id.length - 8) : order.id;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F5F0),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Order ID: $shortId',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF212121)),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Date: ${DateFormat('dd MMM, yyyy  hh:mm a').format(order.createdAt)}',
                                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                                ),
                                                const SizedBox(height: 8),
                                                ...pendingItems.map(
                                                  (pi) => Padding(
                                                    padding: const EdgeInsets.only(bottom: 3.0),
                                                    child: Text(
                                                      '• ${pi.product.name} (Pending: ${pi.pendingQuantity} of ${pi.quantity})',
                                                      style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Action Buttons
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Row(
                                                children: [
                                                  // Call
                                                  InkWell(
                                                    onTap: () => _callCustomer(order.customerPhone),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF2E7D32)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // WhatsApp
                                                  InkWell(
                                                    onTap: () {
                                                      try {
                                                        WhatsAppService.shareOrderToNumber(order, order.customerPhone);
                                                      } catch (e) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
                                                        );
                                                      }
                                                    },
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF25D366).withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(Icons.share_rounded, size: 16, color: Color(0xFF25D366)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  // Fulfill
                                                  ElevatedButton(
                                                    onPressed: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (context) => ProcessQuantitiesDialog(order: order),
                                                      );
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF1565C0),
                                                      foregroundColor: Colors.white,
                                                      elevation: 0,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    child: Text(
                                                      'Fulfill',
                                                      style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            ],
                                          )
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared Widgets & Sort Row
  // ---------------------------------------------------------------------------
  Widget _buildSortRow({
    required List<String> options,
    required String current,
    required Function(String) onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.transparent,
      child: Row(
        children: [
          Text(
            'Sort by:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: options.map((opt) {
                  final isSelected = current == opt;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ChoiceChip(
                      label: Text(opt, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      selected: isSelected,
                      selectedColor: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade700),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                        width: 0.8,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      onSelected: (_) => onSelect(opt),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Advanced Filters Bottom Sheet
  // ---------------------------------------------------------------------------
  void _openFilterBottomSheet(BuildContext context, ProductProvider productProvider, List<Order> allOrders) {
    final uniqueCities = _getUniqueCities(allOrders);

    // Temp local variables inside stateful bottom sheet builder to keep current selection until applied
    String tempDateFilter = _dateFilter;
    DateTimeRange? tempCustomRange = _customRange;
    String tempStatusFilter = _statusFilter;
    String? tempSelectedCity = _selectedCity;
    String? tempSelectedProductId = _selectedProductId;
    String? tempSelectedBrand = _selectedBrand;
    String? tempSelectedCategory = _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle line
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Reports',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF212121),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setBottomSheetState(() {
                            tempDateFilter = 'All Time';
                            tempCustomRange = null;
                            tempStatusFilter = 'All Active';
                            tempSelectedCity = null;
                            tempSelectedProductId = null;
                            tempSelectedBrand = null;
                            tempSelectedCategory = null;
                          });
                        },
                        child: const Text('Reset All', style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 10),
                  
                  // Form fields inside a scrollable view
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Date Range
                          _buildBottomSheetLabel('Date Range'),
                          _buildDropdownCard<String>(
                            value: tempDateFilter,
                            onChanged: (val) {
                              if (val != null) setBottomSheetState(() => tempDateFilter = val);
                            },
                            items: [
                              'All Time',
                              'Today',
                              'Last 7 Days',
                              'Last 30 Days',
                              'Last 90 Days',
                              'Custom Range'
                            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                          ),
                          if (tempDateFilter == 'Custom Range') ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final now = DateTime.now();
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(now.year - 5),
                                  lastDate: DateTime(now.year + 1),
                                  initialDateRange: tempCustomRange,
                                  builder: (ctx, child) => Theme(
                                    data: Theme.of(ctx).copyWith(
                                      colorScheme: const ColorScheme.light(
                                          primary: Color(0xFF2E7D32)),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) {
                                  setBottomSheetState(() => tempCustomRange = picked);
                                }
                              },
                              icon: const Icon(Icons.date_range_rounded,
                                  color: Color(0xFF2E7D32)),
                              label: Text(
                                tempCustomRange == null
                                    ? 'Pick start & end date'
                                    : '${DateFormat('dd MMM yyyy').format(tempCustomRange!.start)} – ${DateFormat('dd MMM yyyy').format(tempCustomRange!.end)}',
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF2E7D32)),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 46),
                                side: const BorderSide(color: Color(0xFF2E7D32)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                          
                          // 2. Order Status
                          _buildBottomSheetLabel('Order Status'),
                          _buildDropdownCard<String>(
                            value: tempStatusFilter,
                            onChanged: (val) {
                              if (val != null) setBottomSheetState(() => tempStatusFilter = val);
                            },
                            items: ['All Active', 'Delivered Only', 'Pending / Partially Pending']
                                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                .toList(),
                          ),
                          
                          // 3. Category
                          _buildBottomSheetLabel('Product Category'),
                          _buildDropdownCard<String?>(
                            value: tempSelectedCategory,
                            onChanged: (val) => setBottomSheetState(() => tempSelectedCategory = val),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Categories')),
                              ...productProvider.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                            ],
                          ),
                          
                          // 4. Brand
                          _buildBottomSheetLabel('Brand'),
                          _buildDropdownCard<String?>(
                            value: tempSelectedBrand,
                            onChanged: (val) => setBottomSheetState(() => tempSelectedBrand = val),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Brands')),
                              ...productProvider.brands.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                            ],
                          ),
                          
                          // 5. Product
                          _buildBottomSheetLabel('Specific Product'),
                          _buildDropdownCard<String?>(
                            value: tempSelectedProductId,
                            onChanged: (val) => setBottomSheetState(() => tempSelectedProductId = val),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Products')),
                              ...productProvider.adminProducts.map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text('${p.name} (${p.brand})', overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                          ),
                          
                          // 6. City / Village
                          _buildBottomSheetLabel('Specific City/Village'),
                          _buildDropdownCard<String?>(
                            value: tempSelectedCity,
                            onChanged: (val) => setBottomSheetState(() => tempSelectedCity = val),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Cities/Villages')),
                              ...uniqueCities.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                  
                  const Divider(height: 24),
                  
                  // Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Cancel', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _dateFilter = tempDateFilter;
                              _customRange = tempCustomRange;
                              _statusFilter = tempStatusFilter;
                              _selectedCity = tempSelectedCity;
                              _selectedProductId = tempSelectedProductId;
                              _selectedBrand = tempSelectedBrand;
                              _selectedCategory = tempSelectedCategory;
                            });
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Apply Filters', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomSheetLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildDropdownCard<T>({
    required T value,
    required ValueChanged<T?> onChanged,
    required List<DropdownMenuItem<T>> items,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.outfit(
            color: const Color(0xFF212121),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers Classes
// ---------------------------------------------------------------------------
class _ProductSalesData {
  final Product product;
  int totalSold = 0;
  double totalRevenue = 0.0;
  int pendingQty = 0;
  final List<Order> pendingOrders = [];

  _ProductSalesData(this.product);
}

class _CitySalesData {
  final String cityName;
  int orderCount = 0;
  int totalUnitsSold = 0;
  double totalRevenue = 0.0;
  final Set<String> customerPhones = {};
  final Map<String, int> productQuantities = {};

  _CitySalesData(this.cityName);

  String get topProduct {
    if (productQuantities.isEmpty) return 'None';
    var topName = 'None';
    var maxQty = 0;
    productQuantities.forEach((name, qty) {
      if (qty > maxQty) {
        maxQty = qty;
        topName = name;
      }
    });
    return '$topName ($maxQty)';
  }
}

class _CustomerSalesData {
  final String name;
  final String phone;
  final String village;
  int totalUnitsPurchased = 0;
  double totalRevenueSpent = 0.0;
  int pendingQty = 0;
  final List<Order> pendingOrders = [];

  _CustomerSalesData({
    required this.name,
    required this.phone,
    required this.village,
  });
}
