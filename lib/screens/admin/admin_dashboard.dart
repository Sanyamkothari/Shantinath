import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _showSyncConfirmDialog(BuildContext context, ProductProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sync Local Catalog',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will overwrite the default products in Firestore with the current local product definitions (SP001 to SP113). Any custom edits to these default products on Firebase will be reset. Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing catalog to Firebase...')),
              );
              await provider.syncDefaultCatalog();
              if (context.mounted) {
                if (provider.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${provider.errorMessage}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Catalog synced successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('Sync Now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final orderProvider = context.watch<OrderProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;

    final canViewSalesReports = authProvider.can('viewSalesReports');
    final canManageProducts = authProvider.can('manageProducts');
    final canManageOrders = authProvider.can('manageOrders');
    final canViewCustomerDirectory = authProvider.can('viewCustomerDirectory');
    final canViewCustomerBalances = authProvider.can('viewCustomerBalances');
    final canManageBanners = authProvider.can('manageBanners');
    final canManageBroadcasts = authProvider.can('manageBroadcasts');
    final canManageEmployees = authProvider.can('manageEmployees');
    final canViewAuditLogs = authProvider.can('viewAuditLogs');

    final totalProducts = productProvider.adminProducts.length;
    final totalOrders = orderProvider.orders.length;
    final pendingOrders = orderProvider.pendingCount;

    final now = DateTime.now();
    final todayOrders = orderProvider.orders
        .where((o) =>
            o.createdAt.year == now.year &&
            o.createdAt.month == now.month &&
            o.createdAt.day == now.day)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isMarathi ? 'स्टाफ पॅनेल' : 'Staff Panel',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isMarathi ? AppConstants.appNameMr : AppConstants.appName,
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isMarathi ? 'डॅशबोर्ड विहंगावलोकन' : 'Dashboard Overview',
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Stats section (only visible if permitted)
              if (canViewSalesReports) ...[
                Text(
                  isMarathi ? 'आकडेवारी' : 'Statistics',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 12),

                // Stats cards grid
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.25,
                  children: [
                    _StatCard(
                      icon: Icons.inventory_2_rounded,
                      value: totalProducts.toString(),
                      label: isMarathi ? 'एकूण उत्पादने' : 'Total Products',
                      gradient: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                    ),
                    _StatCard(
                      icon: Icons.receipt_long_rounded,
                      value: totalOrders.toString(),
                      label: isMarathi ? 'एकूण ऑर्डर' : 'Total Orders',
                      gradient: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
                    ),
                    _StatCard(
                      icon: Icons.pending_actions_rounded,
                      value: pendingOrders.toString(),
                      label: isMarathi ? 'प्रलंबित ऑर्डर' : 'Pending Orders',
                      gradient: const [Color(0xFFFF8F00), Color(0xFFFFCA28)],
                    ),
                    _StatCard(
                      icon: Icons.today_rounded,
                      value: todayOrders.toString(),
                      label: isMarathi ? 'आजच्या ऑर्डर' : "Today's Orders",
                      gradient: const [Color(0xFFE65100), Color(0xFFFF7043)],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // Quick Actions section title
              Text(
                isMarathi ? 'त्वरित कृती' : 'Quick Actions',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(height: 12),

              // Quick action cards
              if (canManageProducts) ...[
                _QuickActionCard(
                  icon: Icons.inventory_rounded,
                  title: isMarathi ? 'उत्पादने व्यवस्थापन' : 'Manage Products',
                  subtitle: isMarathi ? 'उत्पादने जोडा, सुधारा किंवा काढा' : 'Add, edit, or remove products',
                  color: const Color(0xFF2E7D32),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageProducts,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              if (canManageOrders) ...[
                _QuickActionCard(
                  icon: Icons.shopping_bag_rounded,
                  title: isMarathi ? 'ऑर्डर व्यवस्थापन' : 'Manage Orders',
                  subtitle: isMarathi ? 'ऑर्डरची स्थिती पहा आणि अपडेट करा' : 'View and update order statuses',
                  color: const Color(0xFF1565C0),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageOrders,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canViewCustomerDirectory) ...[
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'customer')
                      .where('isApproved', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final pendingCount = snapshot.data?.docs.length ?? 0;
                    final badgeText = pendingCount > 0 ? '$pendingCount Pending' : null;
                    return _QuickActionCard(
                      icon: Icons.people_rounded,
                      title: isMarathi ? 'ग्राहक निर्देशिका' : 'Customer Directory',
                      subtitle: isMarathi ? 'ग्राहक आणि त्यांची माहिती पहा' : 'Browse customers and contact info',
                      color: const Color(0xFFE65100),
                      badgeText: badgeText,
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.customerDirectory,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              if (canManageProducts) ...[
                _QuickActionCard(
                  icon: Icons.inventory_2_rounded,
                  title: isMarathi ? 'स्टॉक स्थिती' : 'Stock Status',
                  subtitle: isMarathi
                      ? 'Tally मधील सध्याचा साठा (फक्त पाहण्यासाठी)'
                      : 'Current Tally stock levels (view only)',
                  color: const Color(0xFF6A1B9A),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.stockStatus,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canViewCustomerBalances) ...[
                _QuickActionCard(
                  icon: Icons.account_balance_wallet_rounded,
                  title: isMarathi ? 'खतावणी (क्रेडिट/डेबिट)' : 'Ledger Book',
                  subtitle: isMarathi
                      ? 'सर्व ग्राहकांची क्रेडिट/डेबिट शिल्लक'
                      : 'All customers\' credit/debit balances',
                  color: const Color(0xFF00838F),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.allBalances,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canManageBanners) ...[
                _QuickActionCard(
                  icon: Icons.photo_library_rounded,
                  title: isMarathi ? 'बॅनर्स व्यवस्थापन' : 'Manage Banners',
                  subtitle: isMarathi ? 'जाहिरात बॅनर्स जोडा किंवा काढा' : 'Add, edit, or remove promo banners',
                  color: const Color(0xFF9C27B0),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageBanners,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canViewSalesReports) ...[
                _QuickActionCard(
                  icon: Icons.analytics_rounded,
                  title: isMarathi ? 'विक्री अहवाल' : 'Sales Reports',
                  subtitle: isMarathi ? 'उत्पादन आणि शहर निहाय विक्री अहवाल' : 'Product-wise & City-wise breakdown',
                  color: const Color(0xFF00796B),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.salesReports,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canManageBroadcasts) ...[
                _QuickActionCard(
                  icon: Icons.campaign_rounded,
                  title: isMarathi ? 'ब्रॉडकास्ट व्यवस्थापन' : 'Manage Broadcasts',
                  subtitle: isMarathi ? 'घोषणा आणि डीलर अपडेट पाठवा' : 'Send announcements & dealer updates',
                  color: const Color(0xFFD81B60),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.manageBroadcasts,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canManageEmployees) ...[
                _QuickActionCard(
                  icon: Icons.badge_outlined,
                  title: isMarathi ? 'कर्मचारी व्यवस्थापन' : 'Manage Employees',
                  subtitle: isMarathi ? 'कर्मचारी आणि परवानग्या जोडा किंवा काढा' : 'Add/remove employees and permissions',
                  color: Colors.deepOrange,
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.adminEmployees,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canViewAuditLogs) ...[
                _QuickActionCard(
                  icon: Icons.history_rounded,
                  title: isMarathi ? 'कर्मचारी हालचालींचा इतिहास' : 'Employee Tracking',
                  subtitle: isMarathi ? 'कर्मचाऱ्यांच्या कामाचा इतिहास पहा' : 'View action audit logs of employees',
                  color: Colors.blueGrey,
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.employeeTracking,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canManageProducts) ...[
                _QuickActionCard(
                  icon: Icons.sync_rounded,
                  title: isMarathi ? 'कॅटलॉग सिंक करा' : 'Sync Local Catalog',
                  subtitle: isMarathi ? 'स्थानिक उत्पादने फायरस्टोअरवर अपलोड करा' : 'Push updated local product list to Firestore',
                  color: const Color(0xFF00897B),
                  onTap: () => _showSyncConfirmDialog(context, productProvider),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat Card Widget
// ---------------------------------------------------------------------------
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final List<Color> gradient;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Action Card Widget
// ---------------------------------------------------------------------------
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final String? badgeText;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF212121),
                            ),
                          ),
                        ),
                        if (badgeText != null && badgeText!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8F00),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badgeText!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
