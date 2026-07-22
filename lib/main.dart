import 'dart:async';

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
  // Crashlytics so field crashes are visible in the Firebase console.
  runZonedGuarded<Future<void>>(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    // Route Flutter framework errors to Crashlytics.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Route low-level platform/engine errors to Crashlytics.
    binding.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
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
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

