import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/widgets/product_image.dart';

class AddEditProductScreen extends StatefulWidget {
  const AddEditProductScreen({super.key});

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _nameMrController;
  late TextEditingController _packSizeController;
  late TextEditingController _priceController;
  late TextEditingController _descriptionController;
  late TextEditingController _descriptionMrController;
  late TextEditingController _companyCityController;
  late TextEditingController _minOrderController;
  late TextEditingController _packWeightController;

  String? _selectedBrand;
  String? _selectedCategory;
  String? _selectedCropType;
  bool _inStock = true;

  Product? _existingProduct;
  bool _isEditMode = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _nameMrController = TextEditingController();
    _packSizeController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();
    _descriptionMrController = TextEditingController();
    _companyCityController = TextEditingController();
    _minOrderController = TextEditingController();
    _packWeightController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Product) {
        _existingProduct = args;
        _isEditMode = true;
        _nameController.text = args.name;
        _nameMrController.text = args.nameMr;
        _selectedBrand = args.brand;
        _selectedCategory = args.category;
        _selectedCropType = args.cropType;
        _packSizeController.text = args.packSize;
        _priceController.text = args.price.toStringAsFixed(0);
        _descriptionController.text = args.description;
        _descriptionMrController.text = args.descriptionMr;
        _inStock = args.inStock;
        _companyCityController.text = args.companyCity;
        _minOrderController.text = args.minOrder.toString();
        _packWeightController.text = args.packWeight.toString();
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameMrController.dispose();
    _packSizeController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _descriptionMrController.dispose();
    _companyCityController.dispose();
    _minOrderController.dispose();
    _packWeightController.dispose();
    super.dispose();
  }

  void _saveProduct() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBrand == null ||
        _selectedCategory == null ||
        _selectedCropType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill all dropdown fields'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final provider = context.read<ProductProvider>();

    final double priceVal = double.parse(_priceController.text.trim());
    final int minOrderVal = int.tryParse(_minOrderController.text.trim()) ?? 1;
    final double packWeightVal = double.tryParse(_packWeightController.text.trim()) ?? 0.0;

    if (_isEditMode && _existingProduct != null) {
      final updated = _existingProduct!.copyWith(
        name: _nameController.text.trim(),
        nameMr: _nameMrController.text.trim(),
        brand: _selectedBrand!,
        category: _selectedCategory!,
        cropType: _selectedCropType!,
        packSize: _packSizeController.text.trim(),
        price: priceVal,
        description: _descriptionController.text.trim(),
        descriptionMr: _descriptionMrController.text.trim(),
        inStock: _inStock,
        companyCity: _companyCityController.text.trim(),
        minOrder: minOrderVal,
        packWeight: packWeightVal,
      );
      provider.updateProduct(updated);
    } else {
      final newProduct = Product(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        nameMr: _nameMrController.text.trim(),
        brand: _selectedBrand!,
        category: _selectedCategory!,
        cropType: _selectedCropType!,
        packSize: _packSizeController.text.trim(),
        price: priceVal,
        imageUrl: '',
        description: _descriptionController.text.trim(),
        descriptionMr: _descriptionMrController.text.trim(),
        inStock: _inStock,
        createdAt: DateTime.now(),
        companyCity: _companyCityController.text.trim(),
        minOrder: minOrderVal,
        packWeight: packWeightVal,
      );
      provider.addProduct(newProduct);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditMode ? 'Product updated successfully' : 'Product added successfully',
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    Navigator.pop(context);
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF2E7D32), size: 22),
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Product' : 'Add Product',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image placeholder
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.2),
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: (_existingProduct != null && _existingProduct!.imageUrl.isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ProductImage(
                            imageUrl: _existingProduct!.imageUrl,
                            category: _existingProduct!.category,
                            fit: BoxFit.cover,
                            iconSize: 40,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_rounded,
                              size: 40,
                              color: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Add Image',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF2E7D32).withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Section: Basic Info
              _SectionHeader(title: 'Basic Information'),
              const SizedBox(height: 12),

              // Product Name
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration('Product Name (English)', Icons.label_rounded),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter product name' : null,
              ),
              const SizedBox(height: 14),

              // Product Name Marathi
              TextFormField(
                controller: _nameMrController,
                decoration: _inputDecoration('Product Name (Marathi)', Icons.translate_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter Marathi name' : null,
              ),
              const SizedBox(height: 14),

              // Brand dropdown
              DropdownButtonFormField<String>(
                value: _selectedBrand,
                decoration: _inputDecoration('Brand', Icons.business_rounded),
                items: AppConstants.brands
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBrand = v),
                validator: (v) => v == null ? 'Select a brand' : null,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: Colors.white,
              ),
              const SizedBox(height: 14),

              // Category dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: _inputDecoration('Category', Icons.category_rounded),
                items: AppConstants.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
                validator: (v) => v == null ? 'Select a category' : null,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: Colors.white,
              ),
              const SizedBox(height: 14),

              // Crop Type dropdown
              DropdownButtonFormField<String>(
                value: _selectedCropType,
                decoration: _inputDecoration('Crop Type', Icons.eco_rounded),
                items: AppConstants.cropTypes
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCropType = v),
                validator: (v) => v == null ? 'Select crop type' : null,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: Colors.white,
              ),

              const SizedBox(height: 24),

              // Section: Pricing
              _SectionHeader(title: 'Pricing & Packaging'),
              const SizedBox(height: 12),

              // Pack Size
              TextFormField(
                controller: _packSizeController,
                decoration: _inputDecoration('Pack Size (e.g. 1 kg, 500 ml, 20 packets)', Icons.straighten_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter pack size' : null,
              ),
              const SizedBox(height: 14),

              // Price
              TextFormField(
                controller: _priceController,
                decoration: _inputDecoration('Price (₹)', Icons.currency_rupee_rounded),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter price';
                  if (double.tryParse(v.trim()) == null) return 'Enter valid price';
                  if (double.parse(v.trim()) <= 0) return 'Price must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Company City
              TextFormField(
                controller: _companyCityController,
                decoration: _inputDecoration('Company City', Icons.location_city_rounded),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter company city' : null,
              ),
              const SizedBox(height: 14),

              // Minimum Order Quantity
              TextFormField(
                controller: _minOrderController,
                decoration: _inputDecoration('Minimum Order Quantity (units)', Icons.shopping_bag_rounded),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter minimum order quantity';
                  final val = int.tryParse(v.trim());
                  if (val == null || val <= 0) return 'Enter valid quantity';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Pack Weight
              TextFormField(
                controller: _packWeightController,
                decoration: _inputDecoration('Pack Weight (kg)', Icons.scale_rounded),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter pack weight';
                  final val = double.tryParse(v.trim());
                  if (val == null || val < 0) return 'Enter valid weight';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // In Stock toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _inStock
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: _inStock
                              ? const Color(0xFF2E7D32)
                              : Colors.red.shade400,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _inStock ? 'In Stock' : 'Out of Stock',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _inStock
                                ? const Color(0xFF2E7D32)
                                : Colors.red.shade400,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _inStock,
                      onChanged: (v) => setState(() => _inStock = v),
                      activeColor: const Color(0xFF2E7D32),
                      activeTrackColor:
                          const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section: Description
              _SectionHeader(title: 'Description'),
              const SizedBox(height: 12),

              // Description English
              TextFormField(
                controller: _descriptionController,
                decoration: _inputDecoration('Description (English)', Icons.description_rounded),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter description' : null,
              ),
              const SizedBox(height: 14),

              // Description Marathi
              TextFormField(
                controller: _descriptionMrController,
                decoration: _inputDecoration('Description (Marathi)', Icons.translate_rounded),
                maxLines: 3,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter Marathi description' : null,
              ),

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _saveProduct,
                  icon: Icon(
                    _isEditMode ? Icons.save_rounded : Icons.add_rounded,
                  ),
                  label: Text(
                    _isEditMode ? 'Update Product' : 'Add Product',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }
}
