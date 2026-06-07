import 'package:flutter/foundation.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/services/product_service.dart';

/// ChangeNotifier provider for product catalog state.
/// Handles loading, filtering, searching, and admin CRUD operations.
class ProductProvider extends ChangeNotifier {
  final ProductService _productService = ProductService();

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Active filters
  String? _selectedCategory;
  String? _selectedBrand;
  String? _selectedCropType;
  String _searchQuery = '';

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// All loaded products (unfiltered).
  List<Product> get products => List.unmodifiable(_products);

  /// Products marked as featured.
  List<Product> get featuredProducts =>
      _products.where((p) => p.isFeatured).toList();

  /// Products after applying active filters and search query.
  List<Product> get filteredProducts => List.unmodifiable(_filteredProducts);

  /// Whether product data is being loaded.
  bool get isLoading => _isLoading;

  /// The most recent error message, if any.
  String? get errorMessage => _errorMessage;

  /// Currently selected category filter.
  String? get selectedCategory => _selectedCategory;

  /// Currently selected brand filter.
  String? get selectedBrand => _selectedBrand;

  /// Currently selected crop type filter.
  String? get selectedCropType => _selectedCropType;

  /// Current search query.
  String get searchQuery => _searchQuery;

  /// Whether any filter is currently active.
  bool get hasActiveFilters =>
      _selectedCategory != null ||
      _selectedBrand != null ||
      _selectedCropType != null ||
      _searchQuery.isNotEmpty;

  /// Unique brand names from the loaded products.
  List<String> get brands =>
      _products.map((p) => p.brand).toSet().toList()..sort();

  /// Unique category names from the loaded products.
  List<String> get categories =>
      _products.map((p) => p.category).toSet().toList()..sort();

  /// Unique crop type names from the loaded products.
  List<String> get cropTypes =>
      _products.map((p) => p.cropType).toSet().toList()..sort();

  /// Count of products currently in stock.
  int get inStockCount => _products.where((p) => p.inStock).length;

  /// Count of products currently out of stock.
  int get outOfStockCount => _products.where((p) => !p.inStock).length;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  ProductProvider() {
    loadProducts();
  }

  /// Load all products from the service.
  Future<void> loadProducts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _products = await _productService.getAllProducts();
      _applyFilters();
    } on Exception catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search products by [query]. Updates the filtered list.
  void searchProducts(String query) {
    _searchQuery = query.trim();
    _applyFilters();
    notifyListeners();
  }

  /// Filter products by [category].
  void filterByCategory(String? category) {
    _selectedCategory = category;
    _applyFilters();
    notifyListeners();
  }

  /// Filter products by [brand].
  void filterByBrand(String? brand) {
    _selectedBrand = brand;
    _applyFilters();
    notifyListeners();
  }

  /// Filter products by [cropType].
  void filterByCropType(String? cropType) {
    _selectedCropType = cropType;
    _applyFilters();
    notifyListeners();
  }

  /// Clear all active filters and search query.
  void clearFilters() {
    _selectedCategory = null;
    _selectedBrand = null;
    _selectedCropType = null;
    _searchQuery = '';
    _filteredProducts = List<Product>.from(_products);
    notifyListeners();
  }

  /// Get a product by [id] from the loaded list.
  Product? getProductById(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // Admin operations --------------------------------------------------------

  /// Add a new product (admin). Reloads and reapplies filters.
  Future<void> addProduct(Product product) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _productService.addProduct(product);
      await loadProducts();
    } on Exception catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update an existing product (admin). Reloads and reapplies filters.
  Future<void> updateProduct(Product product) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _productService.updateProduct(product);
      await loadProducts();
    } on Exception catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a product by [id] (admin). Reloads and reapplies filters.
  Future<void> deleteProduct(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final deleted = await _productService.deleteProduct(id);
      if (!deleted) {
        _errorMessage = 'Product not found';
      }
      await loadProducts();
    } on Exception catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Apply all active filters and search query to produce [_filteredProducts].
  void _applyFilters() {
    var result = List<Product>.from(_products);

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((p) {
        return p.name.toLowerCase().contains(q) ||
            p.nameMr.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q) ||
            p.cropType.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q) ||
            p.descriptionMr.toLowerCase().contains(q);
      }).toList();
    }

    // Apply category filter
    if (_selectedCategory != null) {
      result = result
          .where((p) =>
              p.category.toLowerCase() == _selectedCategory!.toLowerCase())
          .toList();
    }

    // Apply brand filter
    if (_selectedBrand != null) {
      result = result
          .where(
              (p) => p.brand.toLowerCase() == _selectedBrand!.toLowerCase())
          .toList();
    }

    // Apply crop type filter
    if (_selectedCropType != null) {
      result = result
          .where((p) =>
              p.cropType.toLowerCase() == _selectedCropType!.toLowerCase())
          .toList();
    }

    _filteredProducts = result;
  }
}
