import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/models/cart_item.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/product.dart';

Product _product({String id = 'P1', double price = 100.0}) {
  return Product(
    id: id,
    name: 'Test $id',
    nameMr: 'चाचणी $id',
    brand: 'TestBrand',
    category: 'Seeds',
    cropType: 'Cotton',
    packSize: '1KG',
    price: price,
    imageUrl: '',
    description: 'desc',
    descriptionMr: 'वर्णन',
    createdAt: DateTime(2024, 1, 1),
  );
}

CartItem _item({
  String id = 'P1',
  double price = 100.0,
  int quantity = 10,
  int confirmed = 0,
  int delivered = 0,
}) {
  return CartItem(
    product: _product(id: id, price: price),
    quantity: quantity,
    confirmedQuantity: confirmed,
    deliveredQuantity: delivered,
  );
}

Order _order(List<CartItem> items, {OrderStatus status = OrderStatus.pending}) {
  return Order(
    id: 'ORD-1',
    customerId: '9876543210',
    customerName: 'Test Farmer',
    customerPhone: '9876543210',
    customerVillage: 'Testpur',
    items: items,
    totalAmount: items.fold(0.0, (s, i) => s + i.totalPrice),
    status: status,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('Order.getComputedStatus — single item', () {
    test('nothing processed -> pending', () {
      expect(_order([_item()]).getComputedStatus(), OrderStatus.pending);
    });

    test('some confirmed -> partiallyConfirmed', () {
      expect(
        _order([_item(confirmed: 5)]).getComputedStatus(),
        OrderStatus.partiallyConfirmed,
      );
    });

    test('fully confirmed -> confirmed', () {
      expect(
        _order([_item(confirmed: 10)]).getComputedStatus(),
        OrderStatus.confirmed,
      );
    });

    test('some delivered -> partiallyDelivered', () {
      expect(
        _order([_item(delivered: 5)]).getComputedStatus(),
        OrderStatus.partiallyDelivered,
      );
    });

    test('fully delivered -> delivered', () {
      expect(
        _order([_item(delivered: 10)]).getComputedStatus(),
        OrderStatus.delivered,
      );
    });

    test('confirmed + delivered mix that is not all delivered -> partiallyDelivered', () {
      expect(
        _order([_item(confirmed: 5, delivered: 5)]).getComputedStatus(),
        OrderStatus.partiallyDelivered,
      );
    });
  });

  group('Order.getComputedStatus — multiple items & cancellation', () {
    test('one item fully delivered, one still pending -> partiallyDelivered', () {
      final order = _order([
        _item(id: 'A', delivered: 10),
        _item(id: 'B'),
      ]);
      expect(order.getComputedStatus(), OrderStatus.partiallyDelivered);
    });

    test('all items fully delivered -> delivered', () {
      final order = _order([
        _item(id: 'A', delivered: 10),
        _item(id: 'B', delivered: 10),
      ]);
      expect(order.getComputedStatus(), OrderStatus.delivered);
    });

    test('cancelled status always wins over computed value', () {
      final order = _order(
        [_item(delivered: 10)],
        status: OrderStatus.cancelled,
      );
      expect(order.getComputedStatus(), OrderStatus.cancelled);
    });
  });

  group('Order amount breakdowns', () {
    test('delivered/confirmed/pending amounts split by quantity', () {
      // qty 10 @ ₹100: 4 delivered, 3 confirmed, 3 pending.
      final order = _order([
        _item(price: 100, quantity: 10, confirmed: 3, delivered: 4),
      ]);

      expect(order.deliveredAmount, 4 * 100); // 400
      expect(order.confirmedAmount, 3 * 100); // 300
      expect(order.pendingAmount, 3 * 100); // 300
      expect(order.totalAmount, 10 * 100); // 1000
    });

    test('totalItemCount sums all quantities', () {
      final order = _order([
        _item(id: 'A', quantity: 4),
        _item(id: 'B', quantity: 6),
      ]);
      expect(order.totalItemCount, 10);
    });
  });

  group('Order.isCancellable', () {
    test('pending / confirmed / partiallyConfirmed are cancellable', () {
      for (final s in [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.partiallyConfirmed,
      ]) {
        expect(_order([_item()], status: s).isCancellable, true, reason: '$s');
      }
    });

    test('delivered / cancelled are not cancellable', () {
      for (final s in [OrderStatus.delivered, OrderStatus.cancelled]) {
        expect(_order([_item()], status: s).isCancellable, false, reason: '$s');
      }
    });
  });

  group('OrderStatus localized labels', () {
    test('localizedLabel returns English or Marathi by flag', () {
      expect(OrderStatus.pending.localizedLabel(false), 'Pending');
      expect(OrderStatus.pending.localizedLabel(true), 'प्रलंबित');
      expect(OrderStatus.delivered.localizedLabel(true), 'वितरित केली');
    });
  });
}
