import 'package:cloud_firestore/cloud_firestore.dart';

class PromoBanner {
  final String id;
  final String imageUrl;
  final String title;
  final String targetType; // 'none', 'category', 'brand', 'product', 'url'
  final String targetValue; // e.g. 'Seeds', 'Daftari Agro', 'productId', 'https://...'
  final bool isActive;
  final DateTime createdAt;

  PromoBanner({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.targetType,
    required this.targetValue,
    required this.isActive,
    required this.createdAt,
  });

  PromoBanner copyWith({
    String? id,
    String? imageUrl,
    String? title,
    String? targetType,
    String? targetValue,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return PromoBanner(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      title: title ?? this.title,
      targetType: targetType ?? this.targetType,
      targetValue: targetValue ?? this.targetValue,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory PromoBanner.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['createdAt'] is Timestamp) {
      parsedDate = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is String) {
      parsedDate = DateTime.parse(json['createdAt']);
    } else {
      parsedDate = DateTime.now();
    }

    return PromoBanner(
      id: json['id'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      title: json['title'] ?? '',
      targetType: json['targetType'] ?? 'none',
      targetValue: json['targetValue'] ?? '',
      isActive: json['isActive'] ?? true,
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'title': title,
      'targetType': targetType,
      'targetValue': targetValue,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static List<PromoBanner> getSampleBanners() {
    return [
      PromoBanner(
        id: 'sample_banner_1',
        imageUrl: 'https://images.unsplash.com/photo-1593113598332-cd288d649433?w=800&auto=format&fit=crop&q=60',
        title: 'Premium Quality Seeds',
        targetType: 'category',
        targetValue: 'Seeds',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      PromoBanner(
        id: 'sample_banner_2',
        imageUrl: 'https://images.unsplash.com/photo-1628352081506-e3c43153dd6d?w=800&auto=format&fit=crop&q=60',
        title: 'High-Yield Fertilizers',
        targetType: 'category',
        targetValue: 'Fertilizers',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      PromoBanner(
        id: 'sample_banner_3',
        imageUrl: 'https://images.unsplash.com/photo-1592417817098-8f3d6eb19675?w=800&auto=format&fit=crop&q=60',
        title: 'Exclusive Brand Discounts',
        targetType: 'brand',
        targetValue: 'Daftari Agro',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];
  }
}
