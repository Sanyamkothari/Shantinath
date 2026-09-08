import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/models/promo_banner.dart';

class BannerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _bannersRef => _db.collection('banners');

  static final BannerService _instance = BannerService._internal();
  factory BannerService() => _instance;
  BannerService._internal();

  /// Retrieve all banners, newest first.
  ///
  /// NOTE: This intentionally does NOT seed the collection when it is empty.
  /// Only admins/staff may write `banners` (see firestore.rules), so seeding
  /// as a side-effect of a read threw `permission-denied` for every customer
  /// whose home screen loaded while the collection was empty (a fresh
  /// project, or after an admin deleted the last banner). Admins add banners
  /// from Manage Banners; [PromoBanner.getSampleBanners] stays available as
  /// reference content.
  Future<List<PromoBanner>> getAllBanners() async {
    final snapshot = await _bannersRef.get();

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
