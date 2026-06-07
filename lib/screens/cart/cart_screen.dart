import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/widgets/product_image.dart';

class CartScreen extends StatefulWidget {
  final bool isTab;

  const CartScreen({super.key, this.isTab = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _showQuantityDialog(BuildContext context, CartItem item) {
    final controller = TextEditingController(text: '${item.quantity}');
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          localeProvider.isMarathi ? 'किमान ऑर्डर दाखल करा' : 'Enter Custom Quantity',
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
              localeProvider.isMarathi
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
              localeProvider.isMarathi ? 'रद्द करा' : 'Cancel',
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
                if (val < item.product.minOrder) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        localeProvider.isMarathi
                            ? 'किमान ऑर्डर ${item.product.minOrder} नग असणे आवश्यक आहे!'
                            : 'Minimum order must be at least ${item.product.minOrder} units!',
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else if (val % item.product.minOrder != 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        localeProvider.isMarathi
                            ? 'प्रमाण हे ${item.product.minOrder} च्या पटीत असणे आवश्यक आहे!'
                            : 'Quantity must be a multiple of ${item.product.minOrder}!',
                      ),
                      backgroundColor: Colors.red.shade700,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } else {
                  context.read<CartProvider>().updateQuantity(item.product.id, val);
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
              localeProvider.isMarathi ? 'ठीक आहे' : 'OK',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder() async {
    final cartProvider = context.read<CartProvider>();
    final orderProvider = context.read<OrderProvider>();
    final authProvider = context.read<AuthProvider>();
    final isMarathi = Provider.of<LocaleProvider>(context, listen: false).isMarathi;

    if (cartProvider.items.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: Color(0xFF2E7D32)),
            const SizedBox(width: 10),
            Text(
              isMarathi ? 'ऑर्डरची पुष्टी' : 'Confirm Order',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1B5E20),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMarathi
                  ? 'तुम्ही खालील वस्तूंसाठी ऑर्डर नोंदवत आहात:'
                  : 'You are about to place an order for:',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildDialogRow(
                    isMarathi ? 'वस्तू' : 'Items',
                    isMarathi
                        ? '${cartProvider.itemCount} उत्पादने'
                        : '${cartProvider.itemCount} products',
                  ),
                  const SizedBox(height: 6),
                  _buildDialogRow(
                    isMarathi ? 'एकूण' : 'Total',
                    '₹${cartProvider.totalAmount.toStringAsFixed(0)}',
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              isMarathi ? 'रद्द करा' : 'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isMarathi ? 'ऑर्डर नोंदवा' : 'Place Order'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final user = authProvider.currentUser!;
      await orderProvider.placeOrder(
        customerId: user.id,
        customerName: user.name,
        customerPhone: user.phone,
        customerVillage: user.village,
        items: cartProvider.items,
        notes: _notesController.text.trim(),
      );

      cartProvider.clearCart();
      _notesController.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                isMarathi
                    ? 'ऑर्डर यशस्वीरित्या नोंदवली गेली!'
                    : 'Order placed successfully!',
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMarathi
                ? 'ऑर्डर अयशस्वी: ${e.toString()}'
                : 'Order failed: ${e.toString()}',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Widget _buildDialogRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }

  void _removeItem(CartItem item) {
    final isMarathi = Provider.of<LocaleProvider>(context, listen: false).isMarathi;
    final displayName = isMarathi && item.product.nameMr.isNotEmpty
        ? item.product.nameMr
        : item.product.name;

    context.read<CartProvider>().removeFromCart(item.product.id);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isMarathi
              ? '$displayName कार्टमधून काढून टाकले'
              : '$displayName removed from cart',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: isMarathi ? 'पूर्वतयारी' : 'Undo',
          textColor: const Color(0xFFFF8F00),
          onPressed: () {
            context.read<CartProvider>().addToCart(item.product, item.quantity);
          },
        ),
      ),
    );
  }

  Future<void> _showClearCartDialog(BuildContext context) async {
    final isMarathi = Provider.of<LocaleProvider>(context, listen: false).isMarathi;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              isMarathi ? 'कार्ट रिकामे करा' : 'Clear Cart',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600,
                color: const Color(0xFFC62828),
              ),
            ),
          ],
        ),
        content: Text(
          isMarathi
              ? 'तुम्हाला खात्री आहे की तुम्ही कार्टमधील सर्व वस्तू काढून टाकू इच्छिता?'
              : 'Are you sure you want to remove all items from your cart?',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              isMarathi ? 'रद्द करा' : 'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isMarathi ? 'रिकामे करा' : 'Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<CartProvider>().clearCart();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMarathi ? 'कार्ट रिकामे केले गेले' : 'Cart cleared',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;
    final cartProvider = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: widget.isTab
          ? null
          : AppBar(
              title: Text(
                isMarathi ? 'माझे कार्ट' : 'Shopping Cart',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (cartProvider.items.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                    onPressed: () => _showClearCartDialog(context),
                    tooltip: isMarathi ? 'कार्ट रिकामे करा' : 'Clear Cart',
                  ),
              ],
            ),
      body: Consumer<CartProvider>(
        builder: (context, cartProvider, _) {
          if (cartProvider.items.isEmpty) {
            return _buildEmptyCart();
          }

          return Column(
            children: [
              if (widget.isTab) _buildTabHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    ...cartProvider.items.map((item) => _buildCartItem(item)),
                    const SizedBox(height: 12),
                    _buildNotesField(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
              _buildBottomBar(cartProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabHeader() {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;
    final cartProvider = Provider.of<CartProvider>(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Text(
              isMarathi ? 'माझे कार्ट' : 'Shopping Cart',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1B5E20),
              ),
            ),
            const Spacer(),
            if (cartProvider.items.isNotEmpty)
              TextButton.icon(
                onPressed: () => _showClearCartDialog(context),
                icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                label: Text(
                  isMarathi ? 'रिकामे करा' : 'Clear',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isMarathi ? '${cartProvider.itemCount} वस्तू' : '${cartProvider.itemCount} items',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF2E7D32),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 60,
                color: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isMarathi ? 'तुमचे कार्ट रिकामे आहे' : 'Your cart is empty',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isMarathi ? 'सुरू करण्यासाठी काही उत्पादने जोडा' : 'Add some products to get started',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                if (widget.isTab) {
                  // Navigate to home tab - parent handles this
                } else {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.storefront_rounded, size: 20),
              label: Text(isMarathi ? 'उत्पादने पहा' : 'Browse Products'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    final isMarathi = Provider.of<LocaleProvider>(context).isMarathi;
    final displayName = isMarathi && item.product.nameMr.isNotEmpty
        ? item.product.nameMr
        : item.product.name;

    return Dismissible(
      key: ValueKey(item.product.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _removeItem(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ProductImage(
              imageUrl: item.product.imageUrl,
              category: item.product.category,
              width: 60,
              height: 60,
              iconSize: 28,
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 14),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1B5E20),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeItem(item),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                        tooltip: isMarathi ? 'काढून टाका' : 'Remove',
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.product.brand}${item.product.packSize.isNotEmpty ? ' • ${item.product.packSize}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Quantity controls
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                             _buildSmallQtyButton(
                               Icons.remove_rounded,
                               onPressed: item.quantity > item.product.minOrder
                                   ? () => context
                                       .read<CartProvider>()
                                       .updateQuantity(
                                         item.product.id,
                                         item.quantity - item.product.minOrder,
                                       )
                                   : null,
                             ),
                            InkWell(
                              onTap: () => _showQuantityDialog(context, item),
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 32,
                                child: Center(
                                  child: Text(
                                    '${item.quantity}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _buildSmallQtyButton(
                              Icons.add_rounded,
                              onPressed: () => context
                                  .read<CartProvider>()
                                  .updateQuantity(
                                    item.product.id,
                                    item.quantity + item.product.minOrder,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Subtotal
                      Text(
                        '₹${(item.product.price * item.quantity).toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1B5E20),
                        ),
                      ),
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

  Widget _buildSmallQtyButton(IconData icon, {VoidCallback? onPressed}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        color: onPressed != null ? const Color(0xFF2E7D32) : Colors.grey.shade400,
      ),
    );
  }

  Widget _buildNotesField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note_alt_rounded, size: 18, color: Colors.grey.shade500),
              const SizedBox(width: 8),
              Text(
                isMarathi ? 'ऑर्डर नोट्स (पर्यायी)' : 'Order Notes (optional)',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: isMarathi ? 'काही विशेष सूचना असल्यास लिहा...' : 'Add special instructions...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true,
              fillColor: const Color(0xFFF5F5F0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(CartProvider cartProvider) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMarathi ? 'एकूण रक्कम' : 'Total Amount',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${cartProvider.totalAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.outfit(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1B5E20),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // WhatsApp share
                    Container(
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.only(right: 10),
                      child: IconButton.filledTonal(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isMarathi
                                    ? 'ऑर्डर नोंदवल्यानंतर व्हॉट्सॲपवर शेअर करता येईल'
                                    : 'WhatsApp share available after placing order',
                              ),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.share_rounded, size: 22),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366).withOpacity(0.12),
                          foregroundColor: const Color(0xFF25D366),
                        ),
                      ),
                    ),
                    // Place order
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _placeOrder,
                        icon: const Icon(Icons.shopping_bag_rounded, size: 20),
                        label: Text(
                          isMarathi ? 'ऑर्डर नोंदवा' : 'Place Order',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: const Color(0xFF2E7D32).withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
