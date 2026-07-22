import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/models/promo_banner.dart';

class BannerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _bannersRef => _db.collection('banners');

  static final BannerService _instance = BannerService._internal();
  factory BannerService() => _instance;
  BannerService._internal();

  /// Retrieve all banners. Seeds the database if empty.
  Future<List<PromoBanner>> getAllBanners() async {
    final snapshot = await _bannersRef.get();

    if (snapshot.docs.isEmpty) {
      final samples = PromoBanner.getSampleBanners();
      final batch = _db.batch();

      for (final banner in samples) {
        final docRef = _bannersRef.doc(banner.id);
        batch.set(docRef, banner.toJson());
      }

      await batch.commit();

      final currentSnapshot = await _bannersRef.orderBy('createdAt', descending: true).get();
      return currentSnapshot.docs
          .map((doc) => PromoBanner.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    }

    // Sort by createdAt descending
    final list = snapshot.docs
        .map((doc) => PromoBanner.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Retrieve active banners only.
  Future<List<PromoBanner>> getActiveBanners() async {
    final banners = await getAllBanners();
    return banners.where((b) => b.isActive).toList();
  }

  /// Add a new banner. Generates an ID if empty.
  Future<PromoBanner> addBanner(PromoBanner banner) async {
    final docRef = _bannersRef.doc(banner.id.isEmpty ? null : banner.id);
    final newBanner = banner.copyWith(
      id: docRef.id,
      createdAt: DateTime.now(),
    );
    await docRef.set(newBanner.toJson());
    return newBanner;
  }

  /// Update an existing banner.
  Future<PromoBanner> updateBanner(PromoBanner banner) async {
    await _bannersRef.doc(banner.id).set(banner.toJson());
    return banner;
  }

  /// Delete a banner.
  Future<bool> deleteBanner(String id) async {
    await _bannersRef.doc(id).delete();
    return true;
  }
}
