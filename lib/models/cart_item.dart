import 'product.dart';

/// Represents a single item in the shopping cart.
class CartItem {
  final Product product;
  int quantity;
  int confirmedQuantity;
  int deliveredQuantity;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.confirmedQuantity = 0,
    this.deliveredQuantity = 0,
  });

  /// The total price for this cart item (price × quantity).
  double get totalPrice => product.price * quantity;

  /// The pending quantity yet to be confirmed or delivered.
  int get pendingQuantity => quantity - confirmedQuantity - deliveredQuantity;

  /// Creates a [CartItem] from a JSON map.
  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      quantity: json['quantity'] as int? ?? 1,
      confirmedQuantity: json['confirmedQuantity'] as int? ?? 0,
      deliveredQuantity: json['deliveredQuantity'] as int? ?? 0,
    );
  }

  /// Serializes this [CartItem] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'quantity': quantity,
      'confirmedQuantity': confirmedQuantity,
      'deliveredQuantity': deliveredQuantity,
    };
  }

  /// Returns a copy of this [CartItem] with the given fields replaced.
  CartItem copyWith({
    Product? product,
    int? quantity,
    int? confirmedQuantity,
    int? deliveredQuantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      confirmedQuantity: confirmedQuantity ?? this.confirmedQuantity,
      deliveredQuantity: deliveredQuantity ?? this.deliveredQuantity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem &&
          product == other.product &&
          quantity == other.quantity &&
          confirmedQuantity == other.confirmedQuantity &&
          deliveredQuantity == other.deliveredQuantity;

  @override
  int get hashCode => Object.hash(product, quantity, confirmedQuantity, deliveredQuantity);

  @override
  String toString() =>
      'CartItem(product: ${product.name}, qty: $quantity, confirmed: $confirmedQuantity, delivered: $deliveredQuantity, total: ₹$totalPrice)';
}
