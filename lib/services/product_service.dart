import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/models/product.dart';

/// Service for managing product data with Cloud Firestore.
/// Seeds Firestore with sample products on first load if empty.
class ProductService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _productsRef => _db.collection('products');

  // Singleton pattern
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  /// Returns all products from Firestore.
  /// Seeds the Firestore database if it is empty.
  Future<List<Product>> getAllProducts() async {
    final snapshot = await _productsRef.get();
    
    if (snapshot.docs.isEmpty) {
      // Seed database with sample products if completely empty
      final samples = Product.getSampleProducts();
      final seedBatch = _db.batch();
      
      for (final product in samples) {
        final docRef = _productsRef.doc(product.id);
        seedBatch.set(docRef, product.toJson());
      }
      
      await seedBatch.commit();
      
      final currentSnapshot = await _productsRef.orderBy('createdAt', descending: true).get();
      return currentSnapshot.docs
          .map((doc) => Product.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    }
    
    return snapshot.docs
        .map((doc) => Product.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Returns a product by its [id] from Firestore, or null if not found.
  Future<Product?> getProductById(String id) async {
    final doc = await _productsRef.doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return Product.fromJson(data);
  }

  /// Returns all products in the given [category].
  Future<List<Product>> getProductsByCategory(String category) async {
    final products = await getAllProducts();
    return products
        .where((p) => p.category.toLowerCase() == category.toLowerCase())
        .toList();
  }

  /// Returns all products from the given [brand].
  Future<List<Product>> getProductsByBrand(String brand) async {
    final products = await getAllProducts();
    return products
        .where((p) => p.brand.toLowerCase() == brand.toLowerCase())
        .toList();
  }

  /// Returns all products matching the given [cropType].
  Future<List<Product>> getProductsByCropType(String cropType) async {
    final products = await getAllProducts();
    return products
        .where((p) => p.cropType.toLowerCase() == cropType.toLowerCase())
        .toList();
  }

  /// Searches products by [query] matching against name, nameHi, brand,
  /// category, cropType, and description fields.
  Future<List<Product>> searchProducts(String query) async {
    final products = await getAllProducts();
    if (query.trim().isEmpty) return products;

    final q = query.toLowerCase().trim();
    return products.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.nameMr.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          p.cropType.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.descriptionMr.toLowerCase().contains(q);
    }).toList();
  }

  /// Add a new product to Firestore. Generates a new ID if empty.
  /// Returns the added product.
  Future<Product> addProduct(Product product) async {
    final docRef = _productsRef.doc(product.id.isEmpty ? null : product.id);
    final newProduct = product.copyWith(
      id: docRef.id,
      createdAt: DateTime.now(),
    );
    await docRef.set(newProduct.toJson());
    return newProduct;
  }

  /// Update an existing product in Firestore.
  /// Returns the updated product.
  Future<Product> updateProduct(Product product) async {
    await _productsRef.doc(product.id).set(product.toJson());
    return product;
  }

  /// Delete a product by [id] from Firestore.
  /// Returns true if deleted successfully.
  Future<bool> deleteProduct(String id) async {
    await _productsRef.doc(id).delete();
    return true;
  }

  /// Get all unique brands from Firestore.
  Future<List<String>> getUniqueBrands() async {
    final products = await getAllProducts();
    return products.map((p) => p.brand).toSet().toList()..sort();
  }

  /// Get all unique categories from Firestore.
  Future<List<String>> getUniqueCategories() async {
    final products = await getAllProducts();
    return products.map((p) => p.category).toSet().toList()..sort();
  }

  /// Get all unique crop types from Firestore.
  Future<List<String>> getUniqueCropTypes() async {
    final products = await getAllProducts();
    return products.map((p) => p.cropType).toSet().toList()..sort();
  }
}
