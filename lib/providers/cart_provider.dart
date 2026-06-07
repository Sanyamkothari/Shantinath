import 'package:flutter/foundation.dart';
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/product.dart';

/// ChangeNotifier provider for shopping cart state.
/// Manages cart items, quantities, and computed totals.
class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All items currently in the cart.
  List<CartItem> get items => List.unmodifiable(_items);

  /// Total price of all items in the cart.
  double get totalAmount {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  /// Total number of individual items (sum of all quantities).
  int get itemCount {
    return _items.fold(0, (sum, item) => sum + item.quantity);
  }

  /// Number of distinct products in the cart.
  int get distinctItemCount => _items.length;

  /// Whether the cart is empty.
  bool get isEmpty => _items.isEmpty;

  /// Whether the cart has items.
  bool get isNotEmpty => _items.isNotEmpty;

  /// Check if a product with the given [productId] is in the cart.
  bool isInCart(String productId) {
    return _items.any((item) => item.product.id == productId);
  }

  /// Get the quantity of a product in the cart. Returns 0 if not in cart.
  int getQuantity(String productId) {
    try {
      return _items.firstWhere((item) => item.product.id == productId).quantity;
    } catch (_) {
      return 0;
    }
  }

  /// Get a cart item by product ID. Returns null if not in cart.
  CartItem? getCartItem(String productId) {
    try {
      return _items.firstWhere((item) => item.product.id == productId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Add a [product] to the cart with the given [quantity].
  /// If the product is already in the cart, increments the quantity.
  void addToCart(Product product, [int quantity = 1]) {
    if (quantity <= 0) return;

    final existingIndex =
        _items.indexWhere((item) => item.product.id == product.id);

    if (existingIndex != -1) {
      // If adding in increments (like 1), use minOrder as the step, otherwise use the passed quantity.
      final int qtyToAdd = quantity < product.minOrder ? product.minOrder : quantity;
      _items[existingIndex].quantity += qtyToAdd;
    } else {
      // Enforce minimum order quantity when adding for the first time
      final int initialQty = quantity < product.minOrder ? product.minOrder : quantity;
      _items.add(CartItem(product: product, quantity: initialQty));
    }

    notifyListeners();
  }

  /// Remove a product from the cart by its [productId].
  void removeFromCart(String productId) {
    _items.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  /// Update the quantity of a product in the cart.
  /// If [quantity] is 0 or less, removes the item from the cart.
  void updateQuantity(String productId, int quantity) {
    final index =
        _items.indexWhere((item) => item.product.id == productId);

    if (index != -1) {
      final product = _items[index].product;
      if (quantity < product.minOrder) {
        // Enforce minimum order quantity
        return;
      }
      if (quantity % product.minOrder != 0) {
        // Enforce that quantity must be a multiple of minOrder
        return;
      }
      _items[index].quantity = quantity;
      notifyListeners();
    }
  }

  /// Increment the quantity of a product by its minOrder.
  void incrementQuantity(String productId) {
    final index =
        _items.indexWhere((item) => item.product.id == productId);
    if (index != -1) {
      final product = _items[index].product;
      _items[index].quantity += product.minOrder;
      notifyListeners();
    }
  }

  /// Decrement the quantity of a product by its minOrder.
  void decrementQuantity(String productId) {
    final index =
        _items.indexWhere((item) => item.product.id == productId);
    if (index != -1) {
      final product = _items[index].product;
      if (_items[index].quantity > product.minOrder) {
        _items[index].quantity -= product.minOrder;
        notifyListeners();
      }
    }
  }

  /// Clear all items from the cart.
  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
