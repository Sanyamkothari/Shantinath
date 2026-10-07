import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ---------------------------------------------------------------------------
  // Catalog cache
  //
  // Reading the whole `products` collection costs one Firestore read per
  // product, on every app open, for every customer — the biggest single drain
  // on the Spark plan's 50k reads/day. Instead the catalog is cached on the
  // device and revalidated with ONE read of `app_metadata/catalog_version`,
  // which every product write bumps. Only when that version changed (or the
  // cache is missing / too old) is the full collection fetched again.
  // ---------------------------------------------------------------------------

  static const String _cacheKey = 'catalog_cache_v1';
  static const String _cacheVersionKey = 'catalog_cache_version_v1';
  static const String _cacheTimeKey = 'catalog_cache_time_v1';

  /// Hard ceiling on cache age, so a missing/failed version bump can never leave
  /// a device on a stale catalog for more than a day.
  static const Duration _maxCacheAge = Duration(hours: 24);

  /// Within this window repeated calls skip even the version read.
  static const Duration _memoryTrust = Duration(minutes: 10);

  DocumentReference get _versionRef =>
      _db.collection('app_metadata').doc('catalog_version');

  List<Product>? _memory;
  DateTime? _memoryCheckedAt;

  /// The server's current catalog version, or null if unset / unreachable.
  Future<String?> _fetchRemoteVersion() async {
    try {
      final snap = await _versionRef.get();
      final v = (snap.data() as Map<String, dynamic>?)?['version'];
      return v?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(List<Product> products, String? version) async {
    _memory = products;
    _memoryCheckedAt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKey, jsonEncode(products.map((p) => p.toJson()).toList()));
      await prefs.setString(_cacheVersionKey, version ?? '');
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Could not persist catalog cache: $e');
    }
  }

  Future<void> _clearCache() async {
    _memory = null;
    _memoryCheckedAt = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheVersionKey);
      await prefs.remove(_cacheTimeKey);
    } catch (_) {}
  }

  /// Marks the catalog as changed so other devices refetch. Never throws: a
  /// failed bump is bounded by [_maxCacheAge].
  Future<String?> _bumpVersion() async {
    final v = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      await _versionRef.set({'version': v});
      return v;
    } catch (e) {
      debugPrint('Could not bump catalog version: $e');
      return null;
    }
  }

  /// After this device's own write, applies [mutate] to the cached list and
  /// stores it under the new version, so the editing admin doesn't refetch the
  /// whole catalog after every single edit.
  Future<void> _afterWrite(List<Product> Function(List<Product>) mutate) async {
    final version = await _bumpVersion();
    final current = _memory;
    if (current == null || version == null) {
      await _clearCache();
      return;
    }
    await _saveCache(mutate(List<Product>.from(current)), version);
  }

  Future<List<Product>?> _loadDiskCache(
      {required String? remoteVersion}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final time = DateTime.tryParse(prefs.getString(_cacheTimeKey) ?? '');
      if (raw == null || time == null) return null;

      final age = DateTime.now().difference(time);
      if (age > _maxCacheAge) return null;

      final cachedVersion = prefs.getString(_cacheVersionKey) ?? '';
      // Unreachable server (remoteVersion null) -> serve the cache. Otherwise
      // the versions must match exactly.
      if (remoteVersion != null && remoteVersion != cachedVersion) return null;

      return (jsonDecode(raw) as List)
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Returns all products, served from the device cache unless the catalog
  /// changed. Pass [forceRefresh] to always hit Firestore (pull-to-refresh).
  ///
  /// NOTE: This intentionally does NOT seed the catalog. Seeding writes to the
  /// `products` collection, which Firestore rules restrict to admins
  /// (`allow write: if isAdmin()`); doing it here as a side-effect of a read
  /// would throw `permission-denied` for every customer that opens a fresh
  /// (empty) database. The catalog is seeded explicitly by an admin via
  /// [syncDefaultCatalog] (Admin dashboard → Sync default catalog).
  Future<List<Product>> getAllProducts({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _memoryCheckedAt != null) {
      if (DateTime.now().difference(_memoryCheckedAt!) < _memoryTrust) {
        return _memory!;
      }
    }

    String? remoteVersion;
    if (!forceRefresh) {
      remoteVersion = await _fetchRemoteVersion();
      final cached = await _loadDiskCache(remoteVersion: remoteVersion);
      if (cached != null) {
        _memory = cached;
        _memoryCheckedAt = DateTime.now();
        return cached;
      }
    } else {
      remoteVersion = await _fetchRemoteVersion();
    }

    final snapshot = await _productsRef.get();
    final products = snapshot.docs
        .map((doc) => Product.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
    await _saveCache(products, remoteVersion);
    return products;
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
    await _afterWrite((list) => [...list.where((p) => p.id != newProduct.id), newProduct]);
    return newProduct;
  }

  /// Update an existing product in Firestore.
  /// Returns the updated product.
  Future<Product> updateProduct(Product product) async {
    await _productsRef.doc(product.id).set(product.toJson());
    await _afterWrite((list) {
      final i = list.indexWhere((p) => p.id == product.id);
      if (i == -1) return [...list, product];
      list[i] = product;
      return list;
    });
    return product;
  }

  /// Delete a product by [id] from Firestore.
  /// Returns true if deleted successfully.
  Future<bool> deleteProduct(String id) async {
    await _productsRef.doc(id).delete();
    await _afterWrite((list) => list.where((p) => p.id != id).toList());
    return true;
  }

  /// Overwrites and synchronizes all default local products to Firestore.
  /// This ensures any changes to local catalog definitions are pushed to Firebase.
  Future<void> syncDefaultCatalog() async {
    final samples = Product.getSampleProducts();
    final seedBatch = _db.batch();
    
    for (final product in samples) {
      final docRef = _productsRef.doc(product.id);
      seedBatch.set(docRef, product.toJson());
    }
    
    await seedBatch.commit();
    await _bumpVersion();
    await _clearCache();
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
