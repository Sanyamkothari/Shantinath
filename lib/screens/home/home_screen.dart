import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/widgets/product_card.dart';
import 'package:shantinath_agro/widgets/cart_badge.dart';
import 'package:shantinath_agro/widgets/language_toggle.dart';
import 'package:shantinath_agro/screens/cart/cart_screen.dart';
import 'package:shantinath_agro/screens/orders/order_history_screen.dart';
import 'package:shantinath_agro/screens/profile/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens.addAll([
      _HomeTab(
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onViewCart: () {
          setState(() {
            _currentIndex = 1;
          });
        },
      ),
      const CartScreen(isTab: true),
      const OrderHistoryScreen(isTab: true),
      const ProfileScreen(),
    ]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) {
            _searchFocusNode.unfocus();
          }
        },
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF2E7D32).withValues(alpha: 0.12),
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded, color: Color(0xFF2E7D32)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Badge(
                  isLabelVisible: cart.itemCount > 0,
                  label: Text('${cart.itemCount}'),
                  backgroundColor: const Color(0xFFFF8F00),
                  child: const Icon(Icons.shopping_cart_outlined),
                );
              },
            ),
            selectedIcon: Consumer<CartProvider>(
              builder: (context, cart, child) {
                return Badge(
                  isLabelVisible: cart.itemCount > 0,
                  label: Text('${cart.itemCount}'),
                  backgroundColor: const Color(0xFFFF8F00),
                  child: const Icon(Icons.shopping_cart_rounded, color: Color(0xFF2E7D32)),
                );
              },
            ),
            label: 'Cart',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded, color: Color(0xFF2E7D32)),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: Color(0xFF2E7D32)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onViewCart;

  const _HomeTab({
    required this.searchController,
    required this.searchFocusNode,
    required this.onViewCart,
  });

  String? _getBrandLogo(String brand) {
    switch (brand) {
      case 'Daftari Agro':
        return 'assets/company logos/Daftari.png';
      case 'Kohinoor Seeds':
        return 'assets/company logos/kohinoor.png';
      case 'Pravardhan Seeds':
        return 'assets/company logos/pravardhan.jpg';
      case 'Kurnool Seeds':
        return 'assets/company logos/kurnool.jpg';
      case 'Palmor Seeds':
        return 'assets/company logos/Paplamoor.jpeg';
      case 'Tata Rallis':
        return 'assets/company logos/tataRallis.avif';
      case 'Alpagari Seeds':
        return 'assets/company logos/alpgiri.png';
      case 'Green Gold Seeds':
        return 'assets/company logos/greengold.jpeg';
      default:
        return null;
    }
  }

  Future<void> _launchWhatsAppSupport(BuildContext context) async {
    final cleanPhone = AppConstants.adminPhone.replaceAll('+', '').replaceAll(' ', '').trim();
    final formattedPhone = cleanPhone.startsWith('91') ? cleanPhone : '91$cleanPhone';
    const message = "Hello Shantinath Agro Agency, I would like to place an order or make an inquiry.";
    final encodedMessage = Uri.encodeComponent(message);
    final url = 'https://wa.me/$formattedPhone?text=$encodedMessage';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch WhatsApp. Please install it.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final isFiltered = provider.hasActiveFilters;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2E7D32),
          onRefresh: () async {
            provider.clearFilters();
            searchController.clear();
          },
          child: isFiltered
              ? _buildFilteredCatalog(context, provider, isMarathi)
              : _buildDashboard(context, provider, isMarathi),
        ),
      ),
      bottomNavigationBar: _buildStickyCartSummary(context),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _launchWhatsAppSupport(context),
        backgroundColor: const Color(0xFF25D366),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.chat_bubble_rounded,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget? _buildStickyCartSummary(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    if (cartProvider.isEmpty) return null;

    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final totalCount = cartProvider.itemCount;
    final totalPrice = cartProvider.totalAmount;

    double totalWeight = 0.0;
    for (final item in cartProvider.items) {
      totalWeight += item.quantity * item.product.packWeight;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8F00).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isMarathi ? '$totalCount वस्तू' : '$totalCount Items',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                      ),
                      if (totalWeight > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          isMarathi 
                              ? 'वजन: ${totalWeight.toStringAsFixed(1)} किलो' 
                              : 'Weight: ${totalWeight.toStringAsFixed(1)} kg',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${totalPrice.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onViewCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Row(
                children: [
                  Text(
                    isMarathi ? 'कार्ट पहा' : 'View Cart',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, ProductProvider provider, bool isMarathi) {
    final brands = AppConstants.brands;

    return CustomScrollView(
      slivers: [
        // App bar
        _buildDashboardAppBar(context),
        // Welcome Header & Integrated Search Bar
        SliverToBoxAdapter(child: _buildWelcomeHeader(context, isMarathi)),
        
        // Select Company Title
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Text(
              isMarathi ? 'खरेदीसाठी कंपनी निवडा' : 'Select Company to Shop',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF263238),
              ),
            ),
          ),
        ),

        // Company Logos Grid
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final brand = brands[index];
                final logo = _getBrandLogo(brand);

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.companyProducts,
                          arguments: brand,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Center(
                                child: logo != null
                                    ? Image.asset(
                                        logo,
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stackTrace) {
                                          return _buildBrandInitialsBadge(brand);
                                        },
                                      )
                                    : _buildBrandInitialsBadge(brand),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              brand,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
              childCount: brands.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }

  SliverToBoxAdapter _buildDashboardAppBar(BuildContext context) {
    return SliverToBoxAdapter(
      child: Container(
        color: const Color(0xFF1B5E20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Shantinath Agro',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const LanguageToggle(),
              const SizedBox(width: 4),
              const CartBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(BuildContext context, bool isMarathi) {
    final authProvider = context.watch<AuthProvider>();
    final userName = authProvider.currentUser?.name ?? '';
    final greeting = isMarathi 
        ? 'नमस्कार ${userName.isNotEmpty ? userName : ''}!' 
        : 'Welcome back, ${userName.isNotEmpty ? userName : 'Dealer'}!';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMarathi ? 'शांतीनाथ ॲग्रो एजन्सी' : 'Shantinath Agro Agency',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            greeting,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          // Integrated Search Bar
          TextField(
            controller: searchController,
            focusNode: searchFocusNode,
            onChanged: (value) {
              context.read<ProductProvider>().searchProducts(value);
            },
            decoration: InputDecoration(
              hintText: isMarathi 
                  ? 'बियाणे, खते शोधा...' 
                  : 'Search seeds, fertilizers...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2E7D32)),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                      onPressed: () {
                        searchController.clear();
                        context.read<ProductProvider>().searchProducts('');
                        searchFocusNode.unfocus();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandInitialsBadge(String name) {
    final initials = name.split(' ').map((e) => e[0]).take(2).join('').toUpperCase();
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1B5E20),
        ),
      ),
    );
  }

  Widget _buildFilteredCatalog(BuildContext context, ProductProvider provider, bool isMarathi) {
    return CustomScrollView(
      slivers: [
        // Compact App Bar with back button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1B5E20)),
                  onPressed: () {
                    provider.clearFilters();
                    searchController.clear();
                    searchFocusNode.unfocus();
                  },
                ),
                Text(
                  isMarathi ? 'शोध परिणाम' : 'Search Results',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
                const Spacer(),
                const LanguageToggle(),
                const SizedBox(width: 4),
                const CartBadge(),
              ],
            ),
          ),
        ),
        // Search bar & Filter Button
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    onChanged: (value) {
                      provider.searchProducts(value);
                    },
                    decoration: InputDecoration(
                      hintText: isMarathi ? 'बियाणे, खते शोधा...' : 'Search seeds, fertilizers...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2E7D32)),
                      suffixIcon: provider.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                              onPressed: () {
                                searchController.clear();
                                provider.searchProducts('');
                                searchFocusNode.unfocus();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => _showFilterBottomSheet(context, provider, isMarathi),
                  icon: const Icon(Icons.filter_alt_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    foregroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Current active filters horizontal indicators
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                if (provider.selectedCategory != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(
                        isMarathi
                            ? (AppConstants.categoriesMr[provider.selectedCategory] ?? provider.selectedCategory!)
                            : provider.selectedCategory!,
                      ),
                      onDeleted: () => provider.filterByCategory(null),
                      deleteIconColor: const Color(0xFF2E7D32),
                      backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                    ),
                  ),
                if (provider.selectedBrand != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(provider.selectedBrand!),
                      onDeleted: () => provider.filterByBrand(null),
                      deleteIconColor: const Color(0xFFFF8F00),
                      backgroundColor: const Color(0xFFFF8F00).withValues(alpha: 0.08),
                      side: const BorderSide(color: Color(0xFFFF8F00)),
                    ),
                  ),
                if (provider.selectedCropType != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text(
                        isMarathi
                            ? (AppConstants.cropTypesMr[provider.selectedCropType] ?? provider.selectedCropType!)
                            : provider.selectedCropType!,
                      ),
                      onDeleted: () => provider.filterByCropType(null),
                      deleteIconColor: const Color(0xFFE65100),
                      backgroundColor: const Color(0xFFE65100).withValues(alpha: 0.08),
                      side: const BorderSide(color: Color(0xFFE65100)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Results Count Header
        SliverToBoxAdapter(child: _buildSectionHeader(context)),
        // Product grid
        _buildProductGrid(context),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        final count = provider.filteredProducts.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.watch<LocaleProvider>().isMarathi ? 'उत्पादने' : 'Products',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1B5E20),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  context.watch<LocaleProvider>().isMarathi ? '$count वस्तू' : '$count items',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductGrid(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        final products = provider.filteredProducts;
        final isMarathi = context.watch<LocaleProvider>().isMarathi;

        if (products.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isMarathi ? 'कोणतीही उत्पादने आढळली नाहीत' : 'No products found',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isMarathi ? 'कृपया तुमचे शोध शब्द किंवा फिल्टर बदला' : 'Try adjusting your search or filters',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      provider.clearFilters();
                      searchController.clear();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(isMarathi ? 'फिल्टर्स काढा' : 'Clear Filters'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return ProductCard(product: products[index]);
              },
              childCount: products.length,
            ),
          ),
        );
      },
    );
  }

  void _showFilterBottomSheet(BuildContext context, ProductProvider provider, bool isMarathi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer<ProductProvider>(
          builder: (context, localProvider, _) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isMarathi ? 'फिल्टर निवडा' : 'Refine Products',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
                      if (localProvider.selectedCategory != null ||
                          localProvider.selectedBrand != null ||
                          localProvider.selectedCropType != null)
                        TextButton(
                          onPressed: () {
                            localProvider.clearFilters();
                          },
                          child: Text(
                            isMarathi ? 'सर्व साफ करा' : 'Clear All',
                            style: GoogleFonts.outfit(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Category Filter
                  Text(
                    isMarathi ? 'वर्गवारी' : 'Category',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildFilterChip(
                        label: isMarathi ? 'बियाणे' : 'Seeds',
                        isSelected: localProvider.selectedCategory == 'Seeds',
                        onTap: () {
                          localProvider.filterByCategory(
                            localProvider.selectedCategory == 'Seeds' ? null : 'Seeds'
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: isMarathi ? 'खते' : 'Fertilizers',
                        isSelected: localProvider.selectedCategory == 'Fertilizers',
                        onTap: () {
                          localProvider.filterByCategory(
                            localProvider.selectedCategory == 'Fertilizers' ? null : 'Fertilizers'
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Brand Filter
                  Text(
                    isMarathi ? 'कंपनी / ब्रँड' : 'Company / Brand',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: AppConstants.brands.length,
                      itemBuilder: (context, index) {
                        final brand = AppConstants.brands[index];
                        final isSelected = localProvider.selectedBrand == brand;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildFilterChip(
                            label: brand,
                            isSelected: isSelected,
                            onTap: () {
                              localProvider.filterByBrand(isSelected ? null : brand);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Crop Filter
                  Text(
                    isMarathi ? 'पिकानुसार' : 'Crop Type',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: localProvider.cropTypes.length,
                      itemBuilder: (context, index) {
                        final crop = localProvider.cropTypes[index];
                        final isSelected = localProvider.selectedCropType == crop;
                        final label = isMarathi ? (AppConstants.cropTypesMr[crop] ?? crop) : crop;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildFilterChip(
                            label: label,
                            isSelected: isSelected,
                            onTap: () {
                              localProvider.filterByCropType(isSelected ? null : crop);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        isMarathi ? 'लागू करा' : 'Apply Filters',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade100,
          border: Border.all(
            color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey.shade800,
          ),
        ),
      ),
    );
  }
}
