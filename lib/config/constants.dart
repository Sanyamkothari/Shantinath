import 'dart:ui';

/// Application-wide constants for Shantinath Agro Agency.
class AppConstants {
  AppConstants._();

  // ── App Identity ──────────────────────────────────────────────────────
  static const String appName = 'Shantinath Agro Agency';
  static const String appNameMr = 'शांतीनाथ ॲग्रो एजन्सी';
  static const String appTagline = 'Quality Seeds & Fertilizers for Better Yield';
  static const String appTaglineMr = 'चांगल्या उत्पादनासाठी दर्जेदार बियाणे आणि खते';
  static const String appVersion = '1.0.0';

  // ── Locale ─────────────────────────────────────────────────────────────
  static const Locale defaultLocale = Locale('en');
  static const Locale marathiLocale = Locale('mr');
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('mr'),
  ];

  // ── Brands ─────────────────────────────────────────────────────────────
  static const List<String> brands = [
    'Daftari Agro',
    'Kohinoor Seeds',
    'Pravardhan Seeds',
    'Kurnool Seeds',
    'Palmoor Seeds',
    'Rallies Seeds',
    'Alpagiri Seeds',
    'Greengold Seeds',
    'Rushikesh Seeds',
    'Asian Seeds',
    'Del Super',
    'Shiva Global',
    'Greenfield',
    'Maruti',
  ];

  // ── Categories ─────────────────────────────────────────────────────────
  static const List<String> categories = [
    'Seeds',
    'Fertilizers',
  ];

  static const Map<String, String> categoriesMr = {
    'Seeds': 'बियाणे',
    'Fertilizers': 'खते',
  };

  // ── Crop Types ─────────────────────────────────────────────────────────
  static const List<String> cropTypes = [
    'Cotton',
    'Soybean',
    'Tur',
    'Wheat',
    'Rice',
    'Vegetable',
    'Groundnut',
    'Maize',
    'Mustard',
    'Bajra',
    'Jowar',
    'Jawari',
    'Chana',
    'Tilli',
    'Mung',
  ];

  static const Map<String, String> cropTypesMr = {
    'Cotton': 'कापूस',
    'Soybean': 'सोयाबीन',
    'Tur': 'तूर',
    'Wheat': 'गहू',
    'Rice': 'तांदूळ',
    'Vegetable': 'भाजीपाला',
    'Groundnut': 'भुईमूग',
    'Maize': 'मका',
    'Mustard': 'मोहरी',
    'Bajra': 'बाजरी',
    'Jowar': 'ज्वारी',
    'Jawari': 'ज्वारी',
    'Chana': 'चना (हरभरा)',
    'Tilli': 'तीळ (तिळ्ळी)',
    'Mung': 'मूग',
  };

  // ── Firebase Auth / OTP Config ──────────────────────────────────────────
  // Defaults to REAL Firebase Phone Auth. For local development you can opt in
  // to the mock OTP flow (code 123456) with:
  //   flutter run --dart-define=USE_MOCK_OTP=true
  // Never enable mock OTP in a release build.
  static const bool useMockOtp =
      bool.fromEnvironment('USE_MOCK_OTP', defaultValue: false);
  static const String adminPhone = '9999999999';
  static const String adminName = 'Admin';
  static const String cloudFunctionsRegion = 'us-central1'; // Change if deploying to another region (e.g. asia-south1)

  // ── Seller details (printed on delivery memos) ─────────────────────────
  // TODO: move to an admin-editable Settings screen in Phase 2.
  static const String sellerName = 'Shantinath Agro Agency';
  static const String sellerAddress =
      'Main Road, Arni, Dist. Yavatmal, Maharashtra';
  static const String sellerPhone = '';
  static const String sellerGstNo = '';
  static const String sellerSeedLicence = '';
  static const String sellerFertilizerLicence = '';
  static const String sellerPesticideLicence = '';


  // ── Validation ─────────────────────────────────────────────────────────
  static const int phoneLength = 10;
  static const int otpLength = 6;
  static const int minNameLength = 2;
  static const int maxNameLength = 50;
  static const int maxNotesLength = 500;

  // ── UI Constants ───────────────────────────────────────────────────────
  static const double cardBorderRadius = 16.0;
  static const double buttonBorderRadius = 12.0;
  static const double inputBorderRadius = 12.0;
  static const double pageHorizontalPadding = 16.0;
  static const double pageVerticalPadding = 16.0;
  static const double gridSpacing = 12.0;
  static const int gridCrossAxisCount = 2;
  static const double gridChildAspectRatio = 0.65;
  static const double productImageHeight = 180.0;

  // ── Animation Durations ────────────────────────────────────────────────
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 350);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // ── Placeholder / Default Values ───────────────────────────────────────
  static const String defaultProductImage =
      'https://via.placeholder.com/300x300.png?text=Product';
  static const String currencySymbol = '₹';

  // ── Brand Logo Helper ──────────────────────────────────────────────────
  static String? getBrandLogo(String brand) {
    switch (brand) {
      case 'Daftari Agro':
        return 'assets/company logos/Daftari.png';
      case 'Kohinoor Seeds':
        return 'assets/company logos/kohinoor.png';
      case 'Pravardhan Seeds':
        return 'assets/company logos/pravardhan.jpg';
      case 'Kurnool Seeds':
        return 'assets/company logos/kurnool.jpg';
      case 'Palmoor Seeds':
        return 'assets/company logos/Paplamoor.jpeg';
      case 'Rallies Seeds':
        return 'assets/company logos/tataRallis.avif';
      case 'Alpagiri Seeds':
        return 'assets/company logos/alpgiri.png';
      case 'Greengold Seeds':
        return 'assets/company logos/greengold.jpeg';
      case 'Rushikesh Seeds':
        return 'assets/company logos/Rishikesh.png';
      case 'Del Super':
        return 'assets/company logos/DelSuper.png';
      case 'Shiva Global':
        return 'assets/company logos/Shiva-global.png';
      case 'Maruti':
        return 'assets/company logos/Marutifertochem.jpg';
      case 'Asian Seeds':
        return null;
      default:
        return null;
    }
  }
}

