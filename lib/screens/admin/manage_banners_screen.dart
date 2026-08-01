import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/promo_banner.dart';
import 'package:shantinath_agro/providers/banner_provider.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/services/storage_service.dart';

class ManageBannersScreen extends StatefulWidget {
  const ManageBannersScreen({super.key});

  @override
  State<ManageBannersScreen> createState() => _ManageBannersScreenState();
}

class _ManageBannersScreenState extends State<ManageBannersScreen> {
  @override
  Widget build(BuildContext context) {
    final bannerProvider = context.watch<BannerProvider>();
    final banners = bannerProvider.banners;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Text(
          'Manage Banners',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: bannerProvider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : banners.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: banners.length,
                  itemBuilder: (context, index) {
                    final banner = banners[index];
                    return _buildBannerCard(context, banner);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditBannerSheet(context),
        backgroundColor: const Color(0xFF2E7D32),
        icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white),
        label: Text(
          'Add Banner',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No banners found',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Add some promotional banners to show on the Home page.',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBannerCard(BuildContext context, PromoBanner banner) {
    final bannerProvider = context.read<BannerProvider>();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image Preview
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: banner.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade100,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey.shade400),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        banner.title.isNotEmpty ? banner.title : 'Untitled Banner',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF263238),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: banner.isActive 
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        banner.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: banner.isActive ? const Color(0xFF2E7D32) : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.link_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      'Action: ',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${banner.targetType.toUpperCase()} (${banner.targetValue.isNotEmpty ? banner.targetValue : 'none'})',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Toggle Active state switch
                    Text(
                      'Show on Home: ',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    Switch.adaptive(
                      value: banner.isActive,
                      activeTrackColor: const Color(0xFF2E7D32),
                      onChanged: (val) {
                        bannerProvider.updateBanner(banner.copyWith(isActive: val));
                      },
                    ),
                    const Spacer(),
                    // Edit
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Color(0xFF1565C0)),
                      onPressed: () => _showAddEditBannerSheet(context, banner),
                    ),
                    // Delete
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      onPressed: () => _confirmDelete(context, banner.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Banner',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red.shade700),
        ),
        content: const Text('Are you sure you want to delete this promo banner? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<BannerProvider>().deleteBanner(id);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoveButton(StateSetter setModalState, VoidCallback onRemove) {
    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: () {
          setModalState(() {
            onRemove();
          });
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }

  void _showAddEditBannerSheet(BuildContext context, [PromoBanner? existingBanner]) {
    final isEdit = existingBanner != null;
    final imageController = TextEditingController(text: existingBanner?.imageUrl ?? '');
    final titleController = TextEditingController(text: existingBanner?.title ?? '');
    
    String selectedTargetType = existingBanner?.targetType ?? 'none';
    String selectedTargetValue = existingBanner?.targetValue ?? '';
    bool isActive = existingBanner?.isActive ?? true;

    File? localImageFile;
    bool isUploading = false;
    final ImagePicker picker = ImagePicker();

    final bannerProvider = context.read<BannerProvider>();
    final productProvider = context.read<ProductProvider>();

    Future<void> pickImage(StateSetter setModalState) async {
      try {
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (pickedFile != null) {
          setModalState(() {
            localImageFile = File(pickedFile.path);
            imageController.clear(); // Clear text field if file is picked
          });
        }
      } catch (e) {
        debugPrint('Error picking banner image: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Re-resolve target options based on selected target type
            List<String> dropDownItems = [''];
            if (selectedTargetType == 'category') {
              dropDownItems = AppConstants.categories;
            } else if (selectedTargetType == 'brand') {
              dropDownItems = AppConstants.brands;
            } else if (selectedTargetType == 'product') {
              dropDownItems = productProvider.adminProducts.map((p) => p.id).toList();
            }

            // Ensure selectedTargetValue is valid for the list
            if (selectedTargetValue.isNotEmpty && !dropDownItems.contains(selectedTargetValue) && selectedTargetType != 'url') {
              selectedTargetValue = dropDownItems.first;
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEdit ? 'Edit Promo Banner' : 'Add Promo Banner',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Premium Image Selector Card
                    GestureDetector(
                      onTap: isUploading ? null : () => pickImage(setModalState),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: localImageFile != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(localImageFile!, fit: BoxFit.cover),
                                  _buildRemoveButton(setModalState, () {
                                    localImageFile = null;
                                  }),
                                ],
                              )
                            : imageController.text.trim().isNotEmpty
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: imageController.text.trim(),
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const Center(
                                          child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          color: Colors.red.shade50,
                                          alignment: Alignment.center,
                                          child: const Icon(Icons.broken_image_rounded, color: Colors.red, size: 40),
                                        ),
                                      ),
                                      _buildRemoveButton(setModalState, () {
                                        imageController.clear();
                                      }),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_rounded, size: 48, color: const Color(0xFF2E7D32).withValues(alpha: 0.7)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Upload Banner Image',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF2E7D32),
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap to select from Gallery',
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                      ),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Image URL textfield
                    TextField(
                      controller: imageController,
                      enabled: !isUploading,
                      decoration: InputDecoration(
                        labelText: 'Or enter Image URL link',
                        hintText: 'https://images.unsplash.com/...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.link_rounded),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          if (val.trim().isNotEmpty) {
                            localImageFile = null; // Clear local file if URL is typed
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Title
                    TextField(
                      controller: titleController,
                      enabled: !isUploading,
                      decoration: InputDecoration(
                        labelText: 'Banner Title (Optional)',
                        hintText: 'e.g. Cotton Seeds Special Offer',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Click Action Target Type
                    DropdownButtonFormField<String>(
                      initialValue: selectedTargetType,
                      decoration: InputDecoration(
                        labelText: 'Click Action Target Type',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.ads_click_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('No Action (none)')),
                        DropdownMenuItem(value: 'category', child: Text('Filter Category')),
                        DropdownMenuItem(value: 'brand', child: Text('Open Company Brand Products')),
                        DropdownMenuItem(value: 'product', child: Text('Open Specific Product Details')),
                        DropdownMenuItem(value: 'url', child: Text('Open External Web Link')),
                      ],
                      onChanged: isUploading ? null : (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedTargetType = val;
                            selectedTargetValue = '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Click Action Target Value depending on Type selected
                    if (selectedTargetType != 'none') ...[
                      if (selectedTargetType == 'url')
                        TextField(
                          enabled: !isUploading,
                          decoration: InputDecoration(
                            labelText: 'External URL (Action Target Value)',
                            hintText: 'https://...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.language_rounded),
                          ),
                          onChanged: (val) {
                            selectedTargetValue = val.trim();
                          },
                          controller: TextEditingController(text: selectedTargetValue),
                        )
                      else
                        DropdownButtonFormField<String>(
                          initialValue: selectedTargetValue.isEmpty ? null : selectedTargetValue,
                          decoration: InputDecoration(
                            labelText: 'Destination (Action Target Value)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.gps_fixed_rounded),
                          ),
                          items: dropDownItems.map((item) {
                            String itemLabel = item;
                            if (selectedTargetType == 'product') {
                              final prod = productProvider.getProductById(item);
                              if (prod != null) {
                                itemLabel = '${prod.brand} - ${prod.name}';
                              }
                            }
                            return DropdownMenuItem(
                              value: item,
                              child: SizedBox(
                                width: 220,
                                child: Text(itemLabel, overflow: TextOverflow.ellipsis),
                              ),
                            );
                          }).toList(),
                          onChanged: isUploading ? null : (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedTargetValue = val;
                              });
                            }
                          },
                        ),
                      const SizedBox(height: 16),
                    ],

                    // Switch Active State
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Enable Banner (Is Active)',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                        ),
                        Switch.adaptive(
                          value: isActive,
                          activeTrackColor: const Color(0xFF2E7D32),
                          onChanged: isUploading ? null : (val) {
                            setModalState(() {
                              isActive = val;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isUploading ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isUploading
                                ? null
                                : () async {
                                    if (localImageFile == null && imageController.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please select an image or enter a URL link')),
                                      );
                                      return;
                                    }

                                    setModalState(() {
                                      isUploading = true;
                                    });

                                    try {
                                      String finalImageUrl = imageController.text.trim();

                                      // Upload local file to Storage if picked
                                      if (localImageFile != null) {
                                        final bannerId = isEdit ? existingBanner.id : DateTime.now().millisecondsSinceEpoch.toString();
                                        finalImageUrl = await StorageService().uploadBannerImage(bannerId, localImageFile!);
                                      }

                                      final banner = PromoBanner(
                                        id: isEdit ? existingBanner.id : '',
                                        imageUrl: finalImageUrl,
                                        title: titleController.text.trim(),
                                        targetType: selectedTargetType,
                                        targetValue: selectedTargetValue,
                                        isActive: isActive,
                                        createdAt: isEdit ? existingBanner.createdAt : DateTime.now(),
                                      );

                                      if (isEdit) {
                                        await bannerProvider.updateBanner(banner);
                                      } else {
                                        await bannerProvider.addBanner(banner);
                                      }
                                      
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to save banner: $e'), backgroundColor: Colors.red),
                                        );
                                      }
                                    } finally {
                                      setModalState(() {
                                        isUploading = false;
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isUploading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(isEdit ? 'Save Changes' : 'Add Banner'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

