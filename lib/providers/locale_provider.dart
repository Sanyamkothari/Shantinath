import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ChangeNotifier provider for managing the app's locale (language).
/// Supports English ('en') and Hindi ('hi').
class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  /// The currently active locale.
  Locale get locale => _locale;

  /// Whether the current locale is Marathi.
  bool get isMarathi => _locale.languageCode == 'mr';

  /// Whether the current locale is English.
  bool get isEnglish => _locale.languageCode == 'en';

  /// The display name of the current language.
  String get currentLanguageName => isMarathi ? 'मराठी' : 'English';

  /// Toggle between English and Marathi.
  void toggleLocale() {
    if (_locale.languageCode == 'en') {
      _locale = const Locale('mr');
    } else {
      _locale = const Locale('en');
    }
    notifyListeners();
  }

  /// Set the locale explicitly.
  void setLocale(Locale locale) {
    if (_locale == locale) return;

    // Only support en and mr
    if (locale.languageCode != 'en' && locale.languageCode != 'mr') {
      return;
    }

    _locale = locale;
    notifyListeners();
  }
}
