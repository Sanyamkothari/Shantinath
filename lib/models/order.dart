import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_item.dart';

/// Possible states an order can be in.
enum OrderStatus {
  pending,
  confirmed,
  delivered,
  cancelled,
  partiallyConfirmed,
  partiallyDelivered;

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
      case OrderStatus.partiallyConfirmed:
        return 'Partially Confirmed';
      case OrderStatus.partiallyDelivered:
        return 'Partially Delivered';
    }
  }

  /// User-facing Marathi label (the app's secondary language is Marathi, `mr`).
  String get labelMr {
    switch (this) {
      case OrderStatus.pending:
        return 'प्रलंबित';
      case OrderStatus.confirmed:
        return 'पुष्टी केली';
      case OrderStatus.delivered:
        return 'वितरित केली';
      case OrderStatus.cancelled:
        return 'रद्द केली';
      case OrderStatus.partiallyConfirmed:
        return 'अंशतः पुष्टी केली';
      case OrderStatus.partiallyDelivered:
        return 'अंशतः वितरित केली';
    }
  }

  /// Returns the label for the active locale (Marathi when [isMarathi] is true).
  String localizedLabel(bool isMarathi) => isMarathi ? labelMr : label;

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
  final String placedById;
  final String placedByName;
  final String lastModifiedById;
  final String lastModifiedByName;

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
    this.placedById = '',
    this.placedByName = '',
    this.lastModifiedById = '',
    this.lastModifiedByName = '',
  });

  /// Returns a human-readable status string in English.
  String getStatusText() => status.label;

  /// Returns a human-readable status string in Marathi.
  String getStatusTextMr() => status.labelMr;

  /// Total number of individual items (sum of all quantities).
  int get totalItemCount =>
      items.fold(0, (sum, item) => sum + item.quantity);

  /// Total amount for items that have been delivered.
  double get deliveredAmount =>
      items.fold(0.0, (sum, item) => sum + (item.product.price * item.deliveredQuantity));

  /// Total amount for items that have been confirmed.
  double get confirmedAmount =>
      items.fold(0.0, (sum, item) => sum + (item.product.price * item.confirmedQuantity));

  /// Total amount for items that are still pending.
  double get pendingAmount =>
      items.fold(0.0, (sum, item) => sum + (item.product.price * item.pendingQuantity));

  /// Whether the order contains any pending items/quantities.
  bool get hasPendingItems => items.any((item) => item.pendingQuantity > 0);

  /// Whether the order contains any delivered items/quantities.
  bool get hasDeliveredItems => items.any((item) => item.deliveredQuantity > 0);

  /// Whether the order contains any confirmed items/quantities.
  bool get hasConfirmedItems => items.any((item) => item.confirmedQuantity > 0);

  /// Whether this order can still be cancelled.
  bool get isCancellable =>
      status == OrderStatus.pending ||
      status == OrderStatus.confirmed ||
      status == OrderStatus.partiallyConfirmed;

  /// Computes the overall order status based on individual item quantities.
  OrderStatus getComputedStatus() {
    if (status == OrderStatus.cancelled) return OrderStatus.cancelled;

    bool allDelivered = true;
    bool anyDelivered = false;
    bool allConfirmed = true;
    bool anyConfirmed = false;

    for (final item in items) {
      if (item.deliveredQuantity < item.quantity) {
        allDelivered = false;
      }
      if (item.deliveredQuantity > 0) {
        anyDelivered = true;
      }

      final processedQty = item.confirmedQuantity + item.deliveredQuantity;
      if (processedQty < item.quantity) {
        allConfirmed = false;
      }
      if (item.confirmedQuantity > 0) {
        anyConfirmed = true;
      }
    }

    if (allDelivered) return OrderStatus.delivered;
    if (anyDelivered) return OrderStatus.partiallyDelivered;
    if (allConfirmed) return OrderStatus.confirmed;
    if (anyConfirmed) return OrderStatus.partiallyConfirmed;
    return OrderStatus.pending;
  }

  /// Creates an [Order] from a JSON map.
  factory Order.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['createdAt'] is Timestamp) {
      parsedDate = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is String) {
      parsedDate = DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return Order(
      id: json['id'] as String? ?? '',
      customerId: json['customerId'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerVillage: json['customerVillage'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => CartItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      status: OrderStatus.fromString(json['status'] as String? ?? 'pending'),
      notes: json['notes'] as String? ?? '',
      createdAt: parsedDate,
      placedById: json['placedById'] as String? ?? '',
      placedByName: json['placedByName'] as String? ?? '',
      lastModifiedById: json['lastModifiedById'] as String? ?? '',
      lastModifiedByName: json['lastModifiedByName'] as String? ?? '',
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
      'placedById': placedById,
      'placedByName': placedByName,
      'lastModifiedById': lastModifiedById,
      'lastModifiedByName': lastModifiedByName,
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
    String? placedById,
    String? placedByName,
    String? lastModifiedById,
    String? lastModifiedByName,
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
      placedById: placedById ?? this.placedById,
      placedByName: placedByName ?? this.placedByName,
      lastModifiedById: lastModifiedById ?? this.lastModifiedById,
      lastModifiedByName: lastModifiedByName ?? this.lastModifiedByName,
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
