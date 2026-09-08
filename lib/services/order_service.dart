import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:uuid/uuid.dart';

/// Service for managing orders with Cloud Firestore.
class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _ordersRef => _db.collection('orders');
  final Uuid _uuid = const Uuid();

  // Singleton pattern
  static final OrderService _instance = OrderService._internal();
  factory OrderService() => _instance;
  OrderService._internal();

  /// How many fresh order numbers to try before giving up (see [placeOrder]).
  static const int _maxIdAttempts = 5;

  /// Place a new order in Firestore. Returns the placed order with a generated ID.
  ///
  /// Order numbers are short (`ORD-` + 6 hex digits, ~16.7M values) so they
  /// fit on memos and in chat. That is small enough for two orders to draw the
  /// same number once a few thousand exist, and a plain `set()` would then
  /// silently overwrite the earlier order. The write therefore runs in a
  /// transaction that first checks the number is unused and retries with a
  /// new one if not.
  Future<Order> placeOrder(Order order) async {
    for (var attempt = 0; attempt < _maxIdAttempts; attempt++) {
      final orderId = 'ORD-${_uuid.v4().substring(0, 6).toUpperCase()}';
      final docRef = _ordersRef.doc(orderId);

      final newOrder = order.copyWith(
        id: orderId,
        status: OrderStatus.pending,
        createdAt: DateTime.now(),
      );

      final created = await _db.runTransaction<bool>((txn) async {
        final existing = await txn.get(docRef);
        if (existing.exists) return false;
        txn.set(docRef, newOrder.toJson());
        return true;
      });

      if (created) return newOrder;
    }
    throw Exception(
        'Could not allocate a unique order number. Please try again.');
  }

  /// Get all orders for a specific customer by [customerId] from Firestore.
  /// Sorted by most recent first.
  Future<List<Order>> getOrdersByCustomer(String customerId) async {
    final snapshot = await _ordersRef
        .where('customerId', isEqualTo: customerId)
        .get();

    final orders = snapshot.docs
        .map((doc) => Order.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    // In-memory sort by createdAt descending (Firestore requires compound indexes for combining where + orderby in complex rules, so sorting in memory is safer and extremely fast for customer lists)
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  /// Get all orders from Firestore (admin view). Sorted by most recent first.
  Future<List<Order>> getAllOrders() async {
    final snapshot = await _ordersRef.get();
    
    final orders = snapshot.docs
        .map((doc) => Order.fromJson(doc.data() as Map<String, dynamic>))
        .toList();

    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return orders;
  }

  /// Update the status of an order identified by [orderId] in Firestore.
  /// Returns the updated order.
  Future<Order> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String lastModifiedById = '',
    String lastModifiedByName = '',
  }) async {
    await _ordersRef.doc(orderId).update({
      'status': status.name,
      'lastModifiedById': lastModifiedById,
      'lastModifiedByName': lastModifiedByName,
    });

    final updatedDoc = await _ordersRef.doc(orderId).get();
    if (!updatedDoc.exists) {
      throw Exception('Order with id $orderId not found');
    }

    return Order.fromJson(updatedDoc.data() as Map<String, dynamic>);
  }

  /// Update both the items list and the status of an order identified by [orderId] in Firestore.
  /// Returns the updated order.
  Future<Order> updateOrderItemsAndStatus(
    String orderId,
    List<CartItem> items,
    OrderStatus status, {
    String lastModifiedById = '',
    String lastModifiedByName = '',
  }) async {
    await _ordersRef.doc(orderId).update({
      'items': items.map((item) => item.toJson()).toList(),
      'status': status.name,
      'lastModifiedById': lastModifiedById,
      'lastModifiedByName': lastModifiedByName,
    });

    final updatedDoc = await _ordersRef.doc(orderId).get();
    if (!updatedDoc.exists) {
      throw Exception('Order with id $orderId not found');
    }

    return Order.fromJson(updatedDoc.data() as Map<String, dynamic>);
  }

  /// Get a single order by [id] from Firestore. Returns null if not found.
  Future<Order?> getOrderById(String id) async {
    final doc = await _ordersRef.doc(id).get();
    if (!doc.exists) return null;
    return Order.fromJson(doc.data() as Map<String, dynamic>);
  }

  /// Get the count of orders by status.
  Future<Map<OrderStatus, int>> getOrderStatusCounts() async {
    final orders = await getAllOrders();
    final counts = <OrderStatus, int>{};
    for (final status in OrderStatus.values) {
      counts[status] = orders.where((o) => o.status == status).length;
    }
    return counts;
  }
}
