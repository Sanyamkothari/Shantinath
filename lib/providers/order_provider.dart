import 'package:shantinath_agro/utils/error_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/services/order_service.dart';

/// ChangeNotifier provider for order management state.
/// Wraps [OrderService] and exposes reactive state for the UI.
class OrderProvider extends ChangeNotifier {
  final OrderService _orderService = OrderService();

  List<Order> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All loaded orders.
  List<Order> get orders => List.unmodifiable(_orders);

  /// Whether an order operation is in progress.
  bool get isLoading => _isLoading;

  /// The most recent error message, if any.
  String? get errorMessage => _errorMessage;

  /// Count of pending orders (includes partially confirmed & partially delivered).
  int get pendingCount =>
      _orders.where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.partiallyConfirmed || o.status == OrderStatus.partiallyDelivered).length;

  /// Count of confirmed orders (includes partially confirmed).
  int get confirmedCount =>
      _orders.where((o) => o.status == OrderStatus.confirmed || o.status == OrderStatus.partiallyConfirmed).length;

  /// Count of delivered orders (includes partially delivered).
  int get deliveredCount =>
      _orders.where((o) => o.status == OrderStatus.delivered || o.status == OrderStatus.partiallyDelivered).length;

  /// Count of cancelled orders.
  int get cancelledCount =>
      _orders.where((o) => o.status == OrderStatus.cancelled).length;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Load orders for a specific customer by [customerId].
  Future<void> loadOrders(String customerId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _orders = await _orderService.getOrdersByCustomer(customerId);
    } catch (e) {
      _errorMessage = friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load all orders (admin view).
  Future<void> loadAllOrders() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _orders = await _orderService.getAllOrders();
    } catch (e) {
      _errorMessage = friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Place a new order with the given details and cart items.
  /// Returns the placed [Order] on success, null on failure.
  Future<Order?> placeOrder({
    required String customerId,
    required String customerName,
    required String customerPhone,
    required String customerVillage,
    required List<CartItem> items,
    String notes = '',
    String placedById = '',
    String placedByName = '',
  }) async {
    if (items.isEmpty) {
      _errorMessage = 'Cannot place an order with no items';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final totalAmount =
          items.fold(0.0, (sum, item) => sum + item.totalPrice);

      final order = Order(
        id: '', // Will be assigned by service
        customerId: customerId,
        customerName: customerName,
        customerPhone: customerPhone,
        customerVillage: customerVillage,
        items: items,
        totalAmount: totalAmount,
        status: OrderStatus.pending,
        notes: notes,
        createdAt: DateTime.now(),
        placedById: placedById,
        placedByName: placedByName,
      );

      final placedOrder = await _orderService.placeOrder(order);

      // Add to the beginning of the local list
      _orders.insert(0, placedOrder);

      _isLoading = false;
      notifyListeners();
      return placedOrder;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Update the status of an order identified by [orderId].
  /// Returns true on success, false on failure.
  Future<bool> updateOrderStatus(
    String orderId,
    OrderStatus status, {
    String lastModifiedById = '',
    String lastModifiedByName = '',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedOrder =
          await _orderService.updateOrderStatus(
            orderId,
            status,
            lastModifiedById: lastModifiedById,
            lastModifiedByName: lastModifiedByName,
          );

      // Update in local list
      final index = _orders.indexWhere((o) => o.id == orderId);
      if (index != -1) {
        _orders[index] = updatedOrder;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update the items and status of an order identified by [orderId].
  /// Returns true on success, false on failure.
  Future<bool> updateOrderItemsAndStatus(
    String orderId,
    List<CartItem> items,
    OrderStatus status, {
    String lastModifiedById = '',
    String lastModifiedByName = '',
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updatedOrder =
          await _orderService.updateOrderItemsAndStatus(
            orderId,
            items,
            status,
            lastModifiedById: lastModifiedById,
            lastModifiedByName: lastModifiedByName,
          );

      // Update in local list
      final index = _orders.indexWhere((o) => o.id == orderId);
      if (index != -1) {
        _orders[index] = updatedOrder;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Get a single order by [id] from the loaded list.
  Order? getOrderById(String id) {
    try {
      return _orders.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Clear error message.
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
}
