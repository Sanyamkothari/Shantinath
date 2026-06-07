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
    'Palmor Seeds',
    'Tata Rallis',
    'Alpagari Seeds',
    'Green Gold Seeds',
    'Rishikesh Seeds',
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
    'Wheat',
    'Rice',
    'Vegetable',
    'Soybean',
    'Groundnut',
    'Maize',
    'Mustard',
    'Bajra',
    'Jowar',
    'Pigeon Pea',
  ];

  static const Map<String, String> cropTypesMr = {
    'Cotton': 'कापूस',
    'Wheat': 'गहू',
    'Rice': 'तांदूळ',
    'Vegetable': 'भाजीपाला',
    'Soybean': 'सोयाबीन',
    'Groundnut': 'भुईमूग',
    'Maize': 'मका',
    'Mustard': 'मोहरी',
    'Bajra': 'बाजरी',
    'Jowar': 'ज्वारी',
    'Pigeon Pea': 'तूर',
  };

  // ── Admin Credentials ──────────────────────────────────────────────────
  static const String adminPhone = '9999999999';
  static const String adminPassword = 'admin123';
  static const String adminName = 'Admin';

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
}
