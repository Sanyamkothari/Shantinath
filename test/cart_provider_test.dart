import 'package:flutter_test/flutter_test.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';

/// Builds a minimal [Product] for testing. [minOrder] is the field most of the
/// cart logic keys off, so it is a named parameter.
Product _product({
  String id = 'P1',
  double price = 100.0,
  int minOrder = 1,
}) {
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
    minOrder: minOrder,
  );
}

void main() {
  group('CartProvider — minimum order enforcement', () {
    test('first add below minOrder snaps up to minOrder', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20)); // default qty = 1

      expect(cart.getQuantity('P1'), 20);
      expect(cart.distinctItemCount, 1);
    });

    test('adding an existing product increments by at least minOrder', () {
      final cart = CartProvider();
      final p = _product(minOrder: 20);
      cart.addToCart(p); // -> 20
      cart.addToCart(p); // +20 -> 40

      expect(cart.getQuantity('P1'), 40);
      expect(cart.distinctItemCount, 1);
    });

    test('explicit quantity at or above minOrder is respected', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 10), 30);

      expect(cart.getQuantity('P1'), 30);
    });

    test('quantity of zero or less is ignored', () {
      final cart = CartProvider();
      cart.addToCart(_product(), 0);

      expect(cart.isEmpty, true);
    });
  });

  group('CartProvider — updateQuantity validation', () {
    test('rejects a quantity below minOrder', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20), 40);

      cart.updateQuantity('P1', 10); // below min -> ignored
      expect(cart.getQuantity('P1'), 40);
    });

    test('rejects a quantity that is not a multiple of minOrder', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20), 40);

      cart.updateQuantity('P1', 50); // not a multiple of 20 -> ignored
      expect(cart.getQuantity('P1'), 40);
    });

    test('accepts a valid multiple of minOrder', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20), 40);

      cart.updateQuantity('P1', 60);
      expect(cart.getQuantity('P1'), 60);
    });
  });

  group('CartProvider — increment / decrement step by minOrder', () {
    test('increment adds one minOrder step', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20), 20);

      cart.incrementQuantity('P1');
      expect(cart.getQuantity('P1'), 40);
    });

    test('decrement subtracts one step but never below minOrder', () {
      final cart = CartProvider();
      cart.addToCart(_product(minOrder: 20), 40);

      cart.decrementQuantity('P1'); // 40 -> 20
      expect(cart.getQuantity('P1'), 20);

      cart.decrementQuantity('P1'); // already at min -> unchanged
      expect(cart.getQuantity('P1'), 20);
    });
  });

  group('CartProvider — totals and membership', () {
    test('totalAmount, itemCount and distinctItemCount aggregate correctly', () {
      final cart = CartProvider();
      cart.addToCart(_product(id: 'A', price: 100, minOrder: 1), 2);
      cart.addToCart(_product(id: 'B', price: 50, minOrder: 1), 3);

      expect(cart.totalAmount, 100 * 2 + 50 * 3); // 350
      expect(cart.itemCount, 5); // total units
      expect(cart.distinctItemCount, 2); // distinct products
    });

    test('removeFromCart and clearCart empty the cart', () {
      final cart = CartProvider();
      cart.addToCart(_product(id: 'A'), 1);
      cart.addToCart(_product(id: 'B'), 1);

      expect(cart.isInCart('A'), true);
      cart.removeFromCart('A');
      expect(cart.isInCart('A'), false);
      expect(cart.distinctItemCount, 1);

      cart.clearCart();
      expect(cart.isEmpty, true);
    });

    test('getQuantity returns 0 for a product not in the cart', () {
      final cart = CartProvider();
      expect(cart.getQuantity('missing'), 0);
    });
  });
}
