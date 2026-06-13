import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/widgets/product_image.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cartProvider = context.watch<CartProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final isMarathi = localeProvider.isMarathi;

    final inCart = cartProvider.isInCart(product.id);
    final quantity = cartProvider.getQuantity(product.id);

    final String displayName = isMarathi && product.nameMr.isNotEmpty ? product.nameMr : product.name;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () {
          Navigator.pushNamed(
            context,
            AppRoutes.productDetail,
            arguments: product,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image / Icon Section
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    imageUrl: product.imageUrl,
                    category: product.category,
                    iconSize: 48,
                  ),
                  if (!product.inStock)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isMarathi ? 'स्टॉकमध्ये नाही' : 'OUT OF STOCK',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Brand tag
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        product.brand,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: product.category == 'Seeds'
                              ? const Color(0xFF1B5E20)
                              : const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info Section
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.widgets_outlined, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          product.packSize,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹${product.price}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                      if (product.inStock) ...[
                        if (!inCart)
                          InkWell(
                            onTap: () {
                              final int addedQty = product.minOrder;
                              cartProvider.addToCart(product, 1);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isMarathi 
                                        ? '${product.nameMr.isNotEmpty ? product.nameMr : product.name} ($addedQty नग) कार्टमध्ये जोडले गेले' 
                                        : '${product.name} ($addedQty units) added to cart',
                                  ),
                                  duration: const Duration(seconds: 1),
                                  action: SnackBarAction(
                                    label: isMarathi ? 'कार्ट' : 'Cart',
                                    textColor: Colors.greenAccent,
                                    onPressed: () {
                                      Navigator.pushNamed(context, AppRoutes.cart);
                                    },
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          )
                        else
                          Row(
                            children: [
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
                                              ? '${product.nameMr.isNotEmpty ? product.nameMr : product.name} कार्टमधून काढून टाकले'
                                              : '${product.name} removed from cart',
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        action: SnackBarAction(
                                          label: isMarathi ? 'पूर्वतयारी' : 'Undo',
                                          textColor: Colors.greenAccent,
                                          onPressed: () {
                                            cartProvider.addToCart(product, product.minOrder);
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.remove, size: 12),
                                ),
                              ),
                              InkWell(
                                onTap: () => _showQuantityDialog(context, cartProvider, isMarathi),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F0),
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$quantity',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: const Color(0xFF1B5E20),
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  cartProvider.incrementQuantity(product.id);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2E7D32),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.add, size: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
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
