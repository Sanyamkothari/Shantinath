import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/models/promo_banner.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/banner_provider.dart';
import 'package:shantinath_agro/providers/broadcast_provider.dart';
import 'package:shantinath_agro/providers/tab_navigation_provider.dart';
import 'package:shantinath_agro/widgets/cart_badge.dart';
import 'package:shantinath_agro/services/notification_service.dart';
import 'package:shantinath_agro/widgets/language_toggle.dart';
import 'package:shantinath_agro/screens/cart/cart_screen.dart';
import 'package:shantinath_agro/screens/orders/order_history_screen.dart';
import 'package:shantinath_agro/screens/profile/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.initialize(context, context.read<AuthProvider>());
    });
    _screens.addAll([
      _HomeTab(
        onViewShop: () {
          context.read<TabNavigationProvider>().setTab(1);
        },
        onViewCart: () {
          context.read<TabNavigationProvider>().setTab(2);
        },
      ),
      _ShopTab(
        searchController: _searchController,
        searchFocusNode: _searchFocusNode,
        onViewCart: () {
          context.read<TabNavigationProvider>().setTab(2);
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
    final navProvider = context.watch<TabNavigationProvider>();
    final currentIndex = navProvider.currentTab;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(currentIndex, navProvider),
    );
  }

  Widget _buildBottomNav(int currentIndex, TabNavigationProvider navProvider) {
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
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          navProvider.setTab(index);
          if (index != 1) {
            _searchFocusNode.unfocus();
          }
        },
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF2E7D32).withValues(alpha: 0.12),
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded, color: Color(0xFF2E7D32)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront_rounded, color: Color(0xFF2E7D32)),
            label: 'Shop',
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


class _HomeTab extends StatefulWidget {
  final VoidCallback onViewShop;
  final VoidCallback onViewCart;
  const _HomeTab({required this.onViewShop, required this.onViewCart});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      final bannerProvider = context.read<BannerProvider>();
      final banners = bannerProvider.activeBanners;
      if (banners.isNotEmpty) {
        if (_currentPage < banners.length - 1) {
          _currentPage++;
        } else {
          _currentPage = 0;
        }
        if (_pageController.hasClients) {
          _pageController.animateToPage(
            _currentPage,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _launchWhatsAppSupport() async {
    final cleanPhone = AppConstants.businessContactPhone.replaceAll('+', '').replaceAll(' ', '').trim();
    final formattedPhone = cleanPhone.startsWith('91') ? cleanPhone : '91$cleanPhone';
    const message = "Hello Shantinath Agro Agency, I would like to place an order or make an inquiry.";
    final encodedMessage = Uri.encodeComponent(message);
    final url = 'https://wa.me/$formattedPhone?text=$encodedMessage';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch WhatsApp. Please install it.')),
      );
    }
  }

  void _handleBannerClick(PromoBanner banner) {
    if (banner.targetType == 'brand') {
      Navigator.pushNamed(
        context,
        AppRoutes.companyProducts,
        arguments: banner.targetValue,
      );
    } else if (banner.targetType == 'category') {
      context.read<ProductProvider>().filterByCategory(banner.targetValue);
      widget.onViewShop();
    } else if (banner.targetType == 'product') {
      final product = context.read<ProductProvider>().getProductById(banner.targetValue);
      if (product != null) {
        Navigator.pushNamed(
          context,
          AppRoutes.productDetail,
          arguments: product,
        );
      }
    } else if (banner.targetType == 'url') {
      final uri = Uri.tryParse(banner.targetValue);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bannerProvider = context.watch<BannerProvider>();
    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final activeBanners = bannerProvider.activeBanners;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2E7D32),
          onRefresh: () async {
            await bannerProvider.loadBanners();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // App Bar
              SliverToBoxAdapter(child: _buildDashboardAppBar(context)),

              // Welcome Greeting
              SliverToBoxAdapter(child: _buildWelcomeGreeting(context, isMarathi)),

              // Banner sliding container
              SliverToBoxAdapter(
                child: _buildBannerSlider(bannerProvider, activeBanners),
              ),

              // Company Section Title
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    isMarathi ? 'कंपनी निवडा आणि खरेदी करा' : 'Select Company to Shop',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1B5E20),
                    ),
                  ),
                ),
              ),

              // Companies Grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.15,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final brand = AppConstants.brands[index];
                      final logo = AppConstants.getBrandLogo(brand);

                      return InkWell(
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.companyProducts,
                            arguments: brand,
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
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
                              const Divider(height: 1, thickness: 1),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                child: Text(
                                  brand,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF263238),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: AppConstants.brands.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _launchWhatsAppSupport,
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

  Widget _buildDashboardAppBar(BuildContext context) {
    return Container(
      color: const Color(0xFF1B5E20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
            Expanded(
              child: Text(
                'Shantinath Agro',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const LanguageToggle(),
            const SizedBox(width: 4),
            Consumer<BroadcastProvider>(
              builder: (context, broadcastProvider, child) {
                final count = broadcastProvider.unreadCount;
                return IconButton(
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    backgroundColor: const Color(0xFFFF8F00),
                    child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 22),
                  ),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.notifications),
                );
              },
            ),
            const SizedBox(width: 4),
            CartBadge(onTap: widget.onViewCart),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeGreeting(BuildContext context, bool isMarathi) {
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMarathi ? 'शांतीनाथ ॲग्रो एजन्सी' : 'Shantinath Agro Agency',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            greeting,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
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
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1B5E20),
        ),
      ),
    );
  }

  Widget _buildBannerSlider(BannerProvider provider, List<PromoBanner> banners) {
    if (provider.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemCount: banners.length,
              itemBuilder: (context, index) {
                final banner = banners[index];
                return GestureDetector(
                  onTap: () => _handleBannerClick(banner),
                  child: CachedNetworkImage(
                    imageUrl: banner.imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Shimmer.fromColors(
                      baseColor: Colors.grey.shade300,
                      highlightColor: Colors.grey.shade100,
                      child: Container(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_rounded, color: Colors.grey.shade400, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            banner.title.isNotEmpty ? banner.title : 'Promo Offer',
                            style: GoogleFonts.outfit(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              banners.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == index
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF2E7D32).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopTab extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onViewCart;

  const _ShopTab({
    required this.searchController,
    required this.searchFocusNode,
    required this.onViewCart,
  });


  Future<void> _launchWhatsAppSupport(BuildContext context) async {
    final cleanPhone = AppConstants.businessContactPhone.replaceAll('+', '').replaceAll(' ', '').trim();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2E7D32),
          onRefresh: () async {
            provider.clearFilters();
            searchController.clear();
          },
          child: _buildUnifiedDashboard(context, provider, isMarathi),
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

  Widget _buildUnifiedDashboard(BuildContext context, ProductProvider provider, bool isMarathi) {
    return CustomScrollView(
      slivers: [
        // App bar
        _buildDashboardAppBar(context),
        // Welcome Header & Integrated Search Bar
        SliverToBoxAdapter(child: _buildWelcomeHeader(context, isMarathi)),
        
        // Category horizontal scrolling FilterChips
        SliverToBoxAdapter(child: _buildCategoryChips(context)),

        // Crop horizontal scrolling FilterChips
        SliverToBoxAdapter(child: _buildCropChips(context)),

        // Brand horizontal scrolling FilterChips
        SliverToBoxAdapter(child: _buildBrandChips(context)),

        // Active filters row
        _buildActiveFiltersChipsRow(context, provider, isMarathi),

        // Section Title & count
        SliverToBoxAdapter(child: _buildSectionHeader(context)),

        // Row-based Product List
        _buildProductListView(context, provider, isMarathi),

        // Spacer at the bottom
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
              Expanded(
                child: Text(
                  'Shantinath Agro',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const LanguageToggle(),
              const SizedBox(width: 4),
              CartBadge(onTap: onViewCart),
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

  Widget _buildCategoryChips(BuildContext context) {
    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final allLabel = isMarathi ? 'सर्व' : 'All';
    final categories = ['All', ...AppConstants.categories];

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: SizedBox(
        height: 40,
        child: Consumer<ProductProvider>(
          builder: (context, provider, _) {
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final isSelected = (category == 'All' && provider.selectedCategory == null) ||
                    provider.selectedCategory == category;
                final labelText = category == 'All'
                    ? allLabel
                    : (isMarathi ? (AppConstants.categoriesMr[category] ?? category) : category);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      labelText,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF2E7D32),
                      ),
                    ),
                    onSelected: (_) {
                      if (category == 'All') {
                        provider.filterByCategory(null);
                      } else {
                        provider.filterByCategory(category);
                      }
                    },
                    selectedColor: const Color(0xFF2E7D32),
                    backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF2E7D32).withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildCropChips(BuildContext context) {
    final isMarathi = context.watch<LocaleProvider>().isMarathi;
    final allLabel = isMarathi ? 'सर्व पिके' : 'All Crops';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: SizedBox(
        height: 40,
        child: Consumer<ProductProvider>(
          builder: (context, provider, _) {
            final crops = provider.cropTypes;
            final list = ['All', ...crops];

            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final crop = list[index];
                final isSelected = (crop == 'All' && provider.selectedCropType == null) ||
                    provider.selectedCropType == crop;
                
                final labelText = crop == 'All'
                    ? allLabel
                    : (isMarathi ? (AppConstants.cropTypesMr[crop] ?? crop) : crop);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      labelText,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFFE65100),
                      ),
                    ),
                    onSelected: (_) {
                      if (crop == 'All') {
                        provider.filterByCropType(null);
                      } else {
                        provider.filterByCropType(crop);
                      }
                    },
                    selectedColor: const Color(0xFFE65100),
                    backgroundColor: const Color(0xFFE65100).withValues(alpha: 0.08),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFE65100)
                          : const Color(0xFFE65100).withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBrandChips(BuildContext context) {
    final brands = AppConstants.brands;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: SizedBox(
        height: 40,
        child: Consumer<ProductProvider>(
          builder: (context, provider, _) {
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: brands.length,
              itemBuilder: (context, index) {
                final brand = brands[index];
                final isSelected = provider.selectedBrand == brand;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      brand,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFFFF8F00),
                      ),
                    ),
                    onSelected: (_) {
                      if (isSelected) {
                        provider.filterByBrand(null);
                      } else {
                        provider.filterByBrand(brand);
                      }
                    },
                    selectedColor: const Color(0xFFFF8F00),
                    backgroundColor: const Color(0xFFFF8F00).withValues(alpha: 0.08),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFF8F00)
                          : const Color(0xFFFF8F00).withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }


  Widget _buildActiveFiltersChipsRow(BuildContext context, ProductProvider provider, bool isMarathi) {
    if (!provider.hasActiveFilters) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
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
            if (provider.searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text('"${provider.searchQuery}"'),
                  onDeleted: () {
                    searchController.clear();
                    provider.searchProducts('');
                  },
                  deleteIconColor: Colors.blue.shade700,
                  backgroundColor: Colors.blue.shade50,
                  side: BorderSide(color: Colors.blue.shade300),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Consumer<ProductProvider>(
      builder: (context, provider, _) {
        final count = provider.filteredProducts.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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

  Widget _buildProductListView(BuildContext context, ProductProvider provider, bool isMarathi) {
    final products = provider.filteredProducts;

    if (products.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 60,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  isMarathi ? 'कोणतीही उत्पादने आढळली नाहीत' : 'No products found',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMarathi ? 'कृपया तुमचे शोध शब्द किंवा फिल्टर बदला' : 'Try adjusting your search or filters',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 12),
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
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return _ProductRowItem(product: products[index]);
        },
        childCount: products.length,
      ),
    );
  }


}

class _ProductRowItem extends StatelessWidget {
  final Product product;

  const _ProductRowItem({required this.product});

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final isMarathi = context.watch<LocaleProvider>().isMarathi;

    final inCart = cartProvider.isInCart(product.id);
    final quantity = cartProvider.getQuantity(product.id);

    final String displayName =
        isMarathi && product.nameMr.isNotEmpty ? product.nameMr : product.name;

    final categoryLabel = isMarathi
        ? (AppConstants.categoriesMr[product.category] ?? product.category)
        : product.category;

    final cropLabel = isMarathi
        ? (AppConstants.cropTypesMr[product.cropType] ?? product.cropType)
        : product.cropType;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.productDetail,
            arguments: product,
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Product details on the left
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF263238),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Category / Crop and Pack size info
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: product.category == 'Seeds'
                                ? const Color(0xFF1B5E20).withValues(alpha: 0.08)
                                : const Color(0xFFE65100).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$categoryLabel • $cropLabel',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: product.category == 'Seeds'
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.packSize,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Price and Min Order
                    Row(
                      children: [
                        Text(
                          '₹${product.price}',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isMarathi
                              ? '(किमान: ${product.minOrder} नग)'
                              : '(Min: ${product.minOrder} units)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Cart actions on the right
              SizedBox(
                width: 120,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: !product.inStock
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Text(
                            isMarathi ? 'स्टॉकमध्ये नाही' : 'Out of Stock',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : !inCart
                          ? SizedBox(
                              width: 100,
                              height: 36,
                              child: ElevatedButton(
                                onPressed: () {
                                  cartProvider.addToCart(product, product.minOrder);
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isMarathi
                                            ? '$displayName (${product.minOrder} नग) जोडले गेले'
                                            : '$displayName (${product.minOrder} units) added',
                                      ),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  isMarathi ? 'कार्टमध्ये जोडा' : 'Add to Cart',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Minus Button
                                GestureDetector(
                                  onTap: () {
                                    if (quantity > product.minOrder) {
                                      cartProvider.decrementQuantity(product.id);
                                    } else {
                                      cartProvider.removeFromCart(product.id);
                                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            isMarathi
                                                ? '$displayName कार्टमधून काढून टाकले'
                                                : '$displayName removed from cart',
                                          ),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.remove, size: 14, color: Colors.grey.shade700),
                                  ),
                                ),
                                // Quantity Indicator
                                InkWell(
                                  onTap: () => _showQuantityDialog(context, cartProvider, isMarathi),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F0),
                                      border: Border.all(color: Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$quantity',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: const Color(0xFF1B5E20),
                                      ),
                                    ),
                                  ),
                                ),
                                // Plus Button
                                GestureDetector(
                                  onTap: () {
                                    cartProvider.incrementQuantity(product.id);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.add, size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuantityDialog(BuildContext context, CartProvider cartProvider, bool isMarathi) {
    final controller = TextEditingController(text: '${cartProvider.getQuantity(product.id)}');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isMarathi ? 'किमान ऑर्डर दाखल करा' : 'Enter Custom Quantity',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1B5E20),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMarathi
                  ? 'या वस्तूसाठी प्रमाण निर्दिष्ट करा:'
                  : 'Specify the quantity for this cart item:',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'e.g. 100',
                filled: true,
                fillColor: const Color(0xFFF5F5F0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              isMarathi ? 'रद्द करा' : 'Cancel',
              style: GoogleFonts.outfit(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null) {
                if (val < product.minOrder) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMarathi
                            ? 'किमान ऑर्डर ${product.minOrder} नग असणे आवश्यक आहे!'
                            : 'Minimum order must be at least ${product.minOrder} units!',
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else if (val % product.minOrder != 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isMarathi
                            ? 'प्रमाण हे ${product.minOrder} च्या पटीत असणे आवश्यक आहे!'
                            : 'Quantity must be a multiple of ${product.minOrder}!',
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  cartProvider.updateQuantity(product.id, val);
                  Navigator.pop(context);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              isMarathi ? 'ठीक आहे' : 'OK',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
