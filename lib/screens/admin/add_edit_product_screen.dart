import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/services/storage_service.dart';
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
  bool _isVisible = true;

  Product? _existingProduct;
  bool _isEditMode = false;
  bool _initialized = false;

  File? _localImageFile;
  String? _currentImageUrl;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

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
        _isVisible = args.isVisible;
        _companyCityController.text = args.companyCity;
        _minOrderController.text = args.minOrder.toString();
        _packWeightController.text = args.packWeight.toString();
        _currentImageUrl = args.imageUrl;
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _localImageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF2E7D32)),
                title: const Text('Photo Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: Color(0xFF2E7D32)),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProduct() async {
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
    setState(() => _isUploadingImage = true);

    try {
      String finalImageUrl = _currentImageUrl ?? '';

      // Generate or retrieve product ID
      final productId = _isEditMode && _existingProduct != null
          ? _existingProduct!.id
          : DateTime.now().millisecondsSinceEpoch.toString();

      // Handle image upload if a local image has been chosen
      if (_localImageFile != null) {
        finalImageUrl = await StorageService().uploadProductImage(productId, _localImageFile!);
      }

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
          imageUrl: finalImageUrl,
          description: _descriptionController.text.trim(),
          descriptionMr: _descriptionMrController.text.trim(),
          inStock: _inStock,
          isVisible: _isVisible,
          companyCity: _companyCityController.text.trim(),
          minOrder: minOrderVal,
          packWeight: packWeightVal,
        );
        await provider.updateProduct(updated);
      } else {
        final newProduct = Product(
          id: productId,
          name: _nameController.text.trim(),
          nameMr: _nameMrController.text.trim(),
          brand: _selectedBrand!,
          category: _selectedCategory!,
          cropType: _selectedCropType!,
          packSize: _packSizeController.text.trim(),
          price: priceVal,
          imageUrl: finalImageUrl,
          description: _descriptionController.text.trim(),
          descriptionMr: _descriptionMrController.text.trim(),
          inStock: _inStock,
          isVisible: _isVisible,
          createdAt: DateTime.now(),
          companyCity: _companyCityController.text.trim(),
          minOrder: minOrderVal,
          packWeight: packWeightVal,
        );
        await provider.addProduct(newProduct);
      }

      if (mounted) {
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving product: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
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
                child: GestureDetector(
                  onTap: _isUploadingImage ? null : () => _showImageSourceActionSheet(context),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
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
                        child: _localImageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.file(
                                  _localImageFile!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : (_currentImageUrl != null && _currentImageUrl!.isNotEmpty)
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: ProductImage(
                                      imageUrl: _currentImageUrl!,
                                      category: _selectedCategory ?? '',
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
                      if (_isUploadingImage)
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      if (!_isUploadingImage)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
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
                initialValue: _selectedBrand,
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
                initialValue: _selectedCategory,
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
                initialValue: _selectedCropType,
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
                      activeThumbColor: const Color(0xFF2E7D32),
                      activeTrackColor:
                          const Color(0xFF2E7D32).withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Visibility Status Card
              Container(
                padding: const EdgeInsets.all(16),
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
                          _isVisible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: _isVisible
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.shade500,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isVisible ? 'Visible to Customers' : 'Hidden from Customers',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _isVisible
                                ? const Color(0xFF2E7D32)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isVisible,
                      onChanged: (v) => setState(() => _isVisible = v),
                      activeThumbColor: const Color(0xFF2E7D32),
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
                  onPressed: _isUploadingImage ? null : _saveProduct,
                  icon: _isUploadingImage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _isEditMode ? Icons.save_rounded : Icons.add_rounded,
                        ),
                  label: Text(
                    _isUploadingImage
                        ? 'Uploading & Saving...'
                        : (_isEditMode ? 'Update Product' : 'Add Product'),
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
