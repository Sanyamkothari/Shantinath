import 'cart_item.dart';

/// Possible states an order can be in.
enum OrderStatus {
  pending,
  confirmed,
  delivered,
  cancelled;

  /// User-facing English label.
  String get label {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  /// User-facing Hindi label.
  String get labelHi {
    switch (this) {
      case OrderStatus.pending:
        return 'लंबित';
      case OrderStatus.confirmed:
        return 'पुष्टि हुई';
      case OrderStatus.delivered:
        return 'डिलीवर हो गया';
      case OrderStatus.cancelled:
        return 'रद्द किया गया';
    }
  }

  /// Converts a string value to the corresponding [OrderStatus].
  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => OrderStatus.pending,
    );
  }
}

/// Represents a customer order containing one or more cart items.
class Order {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerVillage;
  final List<CartItem> items;
  final double totalAmount;
  final OrderStatus status;
  final String notes;
  final DateTime createdAt;

  const Order({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerVillage,
    required this.items,
    required this.totalAmount,
    this.status = OrderStatus.pending,
    this.notes = '',
    required this.createdAt,
  });

  /// Returns a human-readable status string in English.
  String getStatusText() => status.label;

  /// Returns a human-readable status string in Hindi.
  String getStatusTextHi() => status.labelHi;

  /// Total number of individual items (sum of all quantities).
  int get totalItemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  /// Whether this order can still be cancelled.
  bool get isCancellable =>
      status == OrderStatus.pending || status == OrderStatus.confirmed;

  /// Creates an [Order] from a JSON map.
  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      customerName: json['customerName'] as String,
      customerPhone: json['customerPhone'] as String,
      customerVillage: json['customerVillage'] as String,
      items: (json['items'] as List<dynamic>)
          .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['totalAmount'] as num).toDouble(),
      status: OrderStatus.fromString(json['status'] as String),
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Serializes this [Order] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerVillage': customerVillage,
      'items': items.map((item) => item.toJson()).toList(),
      'totalAmount': totalAmount,
      'status': status.name,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Returns a copy of this [Order] with the given fields replaced.
  Order copyWith({
    String? id,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerVillage,
    List<CartItem>? items,
    double? totalAmount,
    OrderStatus? status,
    String? notes,
    DateTime? createdAt,
  }) {
    return Order(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerVillage: customerVillage ?? this.customerVillage,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Order && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Order(id: $id, customer: $customerName, status: ${status.label}, ₹$totalAmount)';
}
