import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A widget that renders a product image, supporting both network URLs and local assets,
/// with an elegant fallback container containing a crop category icon and gradient background.
class ProductImage extends StatelessWidget {
  final String imageUrl;
  final String category;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double iconSize;
  final BorderRadius? borderRadius;

  const ProductImage({
    super.key,
    required this.imageUrl,
    required this.category,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize = 28,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (imageUrl.isEmpty) {
      imageWidget = _buildPlaceholder();
    } else if (imageUrl.startsWith('http')) {
      imageWidget = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    } else {
      imageWidget = Image.asset(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    final isSeeds = category.toLowerCase() == 'seeds';
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isSeeds
              ? [
                  const Color(0xFF2E7D32).withOpacity(0.08),
                  const Color(0xFF4CAF50).withOpacity(0.02)
                ]
              : [
                  const Color(0xFFFF8F00).withOpacity(0.08),
                  const Color(0xFFFFB300).withOpacity(0.02)
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          isSeeds ? Icons.eco_rounded : Icons.science_rounded,
          size: iconSize,
          color: isSeeds ? const Color(0xFF2E7D32) : const Color(0xFFFF8F00),
        ),
      ),
    );
  }
}
