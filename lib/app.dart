import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shantinath_agro/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/theme.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/screens/splash/splash_screen.dart';
import 'package:shantinath_agro/screens/auth/login_screen.dart';
import 'package:shantinath_agro/screens/auth/register_screen.dart';
import 'package:shantinath_agro/screens/home/home_screen.dart';
import 'package:shantinath_agro/screens/home/product_detail_screen.dart';
import 'package:shantinath_agro/screens/cart/cart_screen.dart';
import 'package:shantinath_agro/screens/orders/order_history_screen.dart';
import 'package:shantinath_agro/screens/orders/order_detail_screen.dart';
import 'package:shantinath_agro/screens/profile/profile_screen.dart';
import 'package:shantinath_agro/screens/admin/admin_dashboard.dart';
import 'package:shantinath_agro/screens/admin/manage_products_screen.dart';
import 'package:shantinath_agro/screens/admin/add_edit_product_screen.dart';
import 'package:shantinath_agro/screens/admin/manage_orders_screen.dart';
import 'package:shantinath_agro/screens/admin/customer_directory_screen.dart';
import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/models/order.dart';

class ShantinathAgroApp extends StatelessWidget {
  const ShantinathAgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();

    return MaterialApp(
      title: 'Shantinath Agro Agency',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      locale: localeProvider.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('mr'),
      ],
      initialRoute: AppRoutes.splash,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case AppRoutes.splash:
            return _buildRoute(const SplashScreen(), settings);
          case AppRoutes.login:
            return _buildRoute(const LoginScreen(), settings);
          case AppRoutes.register:
            return _buildRoute(const RegisterScreen(), settings);
          case AppRoutes.home:
            return _buildRoute(const HomeScreen(), settings);
          case AppRoutes.productDetail:
            final product = settings.arguments as Product;
            return _buildRoute(ProductDetailScreen(product: product), settings);
          case AppRoutes.cart:
            return _buildRoute(const CartScreen(), settings);
          case AppRoutes.orderHistory:
            return _buildRoute(const OrderHistoryScreen(), settings);
          case AppRoutes.orderDetail:
            final order = settings.arguments as Order;
            return _buildRoute(OrderDetailScreen(order: order), settings);
          case AppRoutes.profile:
            return _buildRoute(const ProfileScreen(), settings);
          case AppRoutes.adminDashboard:
            return _buildRoute(const AdminDashboard(), settings);
          case AppRoutes.manageProducts:
            return _buildRoute(const ManageProductsScreen(), settings);
          case AppRoutes.addEditProduct:
            return _buildRoute(const AddEditProductScreen(), settings);
          case AppRoutes.manageOrders:
            return _buildRoute(const ManageOrdersScreen(), settings);
          case AppRoutes.customerDirectory:
            return _buildRoute(const CustomerDirectoryScreen(), settings);
          default:
            return _buildRoute(const SplashScreen(), settings);
        }
      },
    );
  }

  MaterialPageRoute _buildRoute(Widget page, RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => page,
      settings: settings,
    );
  }
}
