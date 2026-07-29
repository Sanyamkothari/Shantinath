import 'package:shantinath_agro/utils/error_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:shantinath_agro/models/promo_banner.dart';
import 'package:shantinath_agro/services/banner_service.dart';

class BannerProvider extends ChangeNotifier {
  final BannerService _bannerService = BannerService();

  List<PromoBanner> _banners = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<PromoBanner> get banners => List.unmodifiable(_banners);
  List<PromoBanner> get activeBanners => _banners.where((b) => b.isActive).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  BannerProvider() {
    Future.microtask(() => loadBanners());
  }

  Future<void> loadBanners() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _banners = await _bannerService.getAllBanners();
    } catch (e) {
      _errorMessage = friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addBanner(PromoBanner banner) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _bannerService.addBanner(banner);
      await loadBanners();
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateBanner(PromoBanner banner) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _bannerService.updateBanner(banner);
      await loadBanners();
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteBanner(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _bannerService.deleteBanner(id);
      await loadBanners();
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }
}
