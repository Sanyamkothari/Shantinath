import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/app.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/providers/product_provider.dart';
import 'package:shantinath_agro/providers/cart_provider.dart';
import 'package:shantinath_agro/providers/order_provider.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/banner_provider.dart';
import 'package:shantinath_agro/providers/broadcast_provider.dart';
import 'package:shantinath_agro/providers/tab_navigation_provider.dart';

void main() async {
  // runZonedGuarded catches uncaught async errors and forwards them to
  // Crashlytics (on mobile) or debug log (on web).
  runZonedGuarded<Future<void>>(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();

    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyD0JPGvBp5Ua7nuucu-CAD2htm5lucxIwY',
          appId: '1:861234828164:web:2675f5db8a15b460e603d1',
          messagingSenderId: '861234828164',
          projectId: 'shantinath-agro',
          storageBucket: 'shantinath-agro.firebasestorage.app',
        ),
      );
    } else {
      await Firebase.initializeApp();
    }

    // Handle Flutter framework & engine errors on all platforms
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FLUTTER ERROR: ${details.exception}\n${details.stack}');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
    };

    binding.platformDispatcher.onError = (error, stack) {
      debugPrint('PLATFORM ERROR: $error\n$stack');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      return true;
    };

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => CartProvider()),
          ChangeNotifierProvider(create: (_) => OrderProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => BannerProvider()),
          ChangeNotifierProvider(create: (_) => BroadcastProvider()),
          ChangeNotifierProvider(create: (_) => TabNavigationProvider()),
        ],
        child: const ShantinathAgroApp(),
      ),
    );
  }, (error, stack) {
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint('Uncaught async error: $error\n$stack');
    }
  });
}

