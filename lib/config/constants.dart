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
  // Designated admin login numbers. On first OTP login each is auto-provisioned
  // as an admin profile in Firestore (see AuthService._fetchOrCreateUserSession)
  // and treated as a protected bootstrap admin by firestore.rules. Keep this list
  // in sync with the isBootstrapAdmin() list in firestore.rules.
  static const List<String> adminPhones = [
    '9422167400',
    '9422167401',
    '9421964383',
    '8669554684',
  ];

  // Customer-facing business contact number used for the WhatsApp "message the
  // shop" links (home screen, whatsapp_service). Defaults to the primary admin
  // number — change if the shop publishes a different public WhatsApp number.
  static const String businessContactPhone = '9422167400';

  static const String adminName = 'Admin';
  static const String cloudFunctionsRegion = 'us-central1'; // Change if deploying to another region (e.g. asia-south1)

  // ── Seller details (printed on tax invoices and delivery memos) ────────
  // Transcribed from the firm's Tally TAX INVOICE. These are regulatory
  // identifiers that appear on legal documents — verify against a printed
  // invoice before changing.
  // TODO: move to an admin-editable Settings screen in Phase 2.
  static const String sellerName = 'SHANTINATH AGRO AGENCIES ARNI 2024-2027';
  static const String sellerAddress =
      'AT POST-ARNI, MAHUR ROAD, DIST YAVATMAL [M.S.]';
  static const String sellerPhone = '9422167401/7798167401';
  static const String sellerEmail = 'shantinathagro97@gmail.com';
  static const String sellerGstNo = '27AGXPK4310L1ZY';
  static const String sellerPan = 'AGXPK4310L';
  static const String sellerStateName = 'Maharashtra';
  static const String sellerStateCode = '27';
  static const String sellerJurisdiction = 'ARNI';

  static const String sellerSeedLicence = 'LCSD0320220381YVT';
  static const String sellerSeedLicence2 = 'LCSD0620221190YVT';
  // Read from the (sharper) credit-note print: LCFWD0620220263YVT.
  // The tax-invoice photo was angled and appeared to carry an extra '2'.
  static const String sellerFertilizerWholesaleLicence = 'LCFWD0620220263YVT';
  static const String sellerFertilizerRetailLicence = 'LCFRD0620222183YVT';
  // Kept for the delivery-memo model, which stores a single fertilizer licence.
  static const String sellerFertilizerLicence = sellerFertilizerWholesaleLicence;
  static const String sellerPesticideLicence = '';

  // Printed under the invoice declaration.
  static const int invoicePaymentDays = 10;
  static const double invoiceOverdueInterestPct = 24;


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

