import 'product.dart';

/// Represents a single item in the shopping cart.
class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });

  /// The total price for this cart item (price × quantity).
  double get totalPrice => product.price * quantity;

  /// Creates a [CartItem] from a JSON map.
  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      quantity: json['quantity'] as int? ?? 1,
    );
  }

  /// Serializes this [CartItem] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'quantity': quantity,
    };
  }

  /// Returns a copy of this [CartItem] with the given fields replaced.
  CartItem copyWith({
    Product? product,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem &&
          product == other.product &&
          quantity == other.quantity;

  @override
  int get hashCode => Object.hash(product, quantity);

  @override
  String toString() =>
      'CartItem(product: ${product.name}, qty: $quantity, total: ₹$totalPrice)';
}
