import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/product_provider.dart';

class CompanyProductsScreen extends StatelessWidget {
  final String brand;

  const CompanyProductsScreen({super.key, required this.brand});

  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final cartProvider = context.watch<CartProvider>();
    final isMarathi = context.watch<LocaleProvider>().isMarathi;

    // Filter products for this company
    final brandProducts = productProvider.products
        .where((p) => p.brand.toLowerCase() == brand.toLowerCase())
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          brand,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        actions: [
          // Cart Badge in App Bar
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Badge(
                isLabelVisible: cartProvider.itemCount > 0,
                label: Text('${cartProvider.itemCount}'),
                backgroundColor: const Color(0xFFFF8F00),
                child: IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // List of products
            Expanded(
              child: brandProducts.isEmpty
                  ? Center(
                      child: Text(
                        isMarathi
                            ? 'या कंपनीचे कोणतेही उत्पादन आढळले नाही.'
                            : 'No products found for this company.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: brandProducts.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final product = brandProducts[index];
                        return _ProductRowItem(product: product);
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildStickyCartSummary(context),
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
              onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
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
                                // Quantity Text Field
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
