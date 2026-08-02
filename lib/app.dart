import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shantinath_agro/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shantinath_agro/config/theme.dart';
import 'package:shantinath_agro/config/routes.dart';
import 'package:shantinath_agro/providers/locale_provider.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';
import 'package:shantinath_agro/screens/splash/splash_screen.dart';
import 'package:shantinath_agro/screens/auth/login_screen.dart';
import 'package:shantinath_agro/screens/auth/register_screen.dart';
import 'package:shantinath_agro/screens/auth/pending_approval_screen.dart';
import 'package:shantinath_agro/screens/home/home_screen.dart';
import 'package:shantinath_agro/screens/home/company_products_screen.dart';
import 'package:shantinath_agro/screens/home/product_detail_screen.dart';
import 'package:shantinath_agro/screens/cart/cart_screen.dart';
import 'package:shantinath_agro/screens/orders/order_history_screen.dart';
import 'package:shantinath_agro/screens/orders/order_detail_screen.dart';
import 'package:shantinath_agro/screens/profile/profile_screen.dart';
import 'package:shantinath_agro/screens/profile/ledger_report_screen.dart';
import 'package:shantinath_agro/screens/admin/admin_dashboard.dart';
import 'package:shantinath_agro/screens/admin/manage_products_screen.dart';
import 'package:shantinath_agro/screens/admin/add_edit_product_screen.dart';
import 'package:shantinath_agro/screens/admin/manage_orders_screen.dart';
import 'package:shantinath_agro/screens/admin/customer_directory_screen.dart';
import 'package:shantinath_agro/screens/admin/all_balances_screen.dart';
import 'package:shantinath_agro/screens/admin/create_delivery_memo_screen.dart';
import 'package:shantinath_agro/screens/admin/stock_status_screen.dart';
import 'package:shantinath_agro/screens/admin/manage_banners_screen.dart';
import 'package:shantinath_agro/screens/admin/sales_reports_screen.dart';
import 'package:shantinath_agro/screens/admin/manage_broadcasts_screen.dart';
import 'package:shantinath_agro/screens/admin/manage_employees_screen.dart';
import 'package:shantinath_agro/screens/admin/employee_permissions_screen.dart';
import 'package:shantinath_agro/screens/admin/employee_tracking_screen.dart';
import 'package:shantinath_agro/screens/home/notifications_screen.dart';

import 'package:shantinath_agro/models/product.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/user_model.dart';

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
      // Clamp the system font scale so very large "Display size / Font size"
      // accessibility settings (common on customers' phones) cannot blow up
      // fixed-height layouts and cause overflow. Text still scales up to 1.3x
      // for readability, but no further.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clampedScaler = mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clampedScaler),
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: AppRoutes.splash,
      onGenerateRoute: (settings) {
        final authProvider = context.read<AuthProvider>();
        final isLoggedIn = authProvider.isLoggedIn;
        final isApproved = authProvider.currentUser?.isApproved ?? false;
        final isStaff = authProvider.isStaff;

        // Centralized Guards: Require login for all screens except splash, login, and register
        if (!isLoggedIn &&
            settings.name != AppRoutes.splash &&
            settings.name != AppRoutes.login &&
            settings.name != AppRoutes.register) {
          return _buildRoute(const LoginScreen(), settings);
        }

        // Centralized Guards: If logged in, but not approved and not staff, restrict to pending approval screen
        if (isLoggedIn &&
            !isStaff &&
            !isApproved &&
            settings.name != AppRoutes.pendingApproval &&
            settings.name != AppRoutes.splash) {
          return _buildRoute(const PendingApprovalScreen(), settings);
        }

        // Centralized Guards: Restrict admin/staff routes to authorized users only
        if (settings.name != null &&
            settings.name!.startsWith('/admin')) {
          if (!isStaff) {
            return _buildRoute(const HomeScreen(), settings);
          }

          // Check permissions for specific admin/staff routes
          String? requiredPermission;
          switch (settings.name) {
            case AppRoutes.manageProducts:
            case AppRoutes.addEditProduct:
              requiredPermission = 'manageProducts';
              break;
            case AppRoutes.manageOrders:
              requiredPermission = 'manageOrders';
              break;
            case AppRoutes.createDeliveryMemo:
              requiredPermission = 'createDeliveryMemo';
              break;
            case AppRoutes.stockStatus:
              requiredPermission = 'manageProducts';
              break;
            case AppRoutes.customerDirectory:
              requiredPermission = 'viewCustomerDirectory';
              break;
            case AppRoutes.allBalances:
              requiredPermission = 'viewCustomerBalances';
              break;
            case AppRoutes.manageBanners:
              requiredPermission = 'manageBanners';
              break;
            case AppRoutes.salesReports:
              requiredPermission = 'viewSalesReports';
              break;
            case AppRoutes.manageBroadcasts:
              requiredPermission = 'manageBroadcasts';
              break;
            case AppRoutes.adminEmployees:
              requiredPermission = 'manageEmployees';
              break;
            case AppRoutes.employeePermissions:
              requiredPermission = 'managePermissions';
              break;
            case AppRoutes.employeeTracking:
              requiredPermission = 'viewAuditLogs';
              break;
          }

          if (requiredPermission != null && !authProvider.can(requiredPermission)) {
            return _buildRoute(const HomeScreen(), settings);
          }
        }

        switch (settings.name) {
          case AppRoutes.splash:
            return _buildRoute(const SplashScreen(), settings);
          case AppRoutes.login:
            if (isLoggedIn) {
              if (!isStaff && !isApproved) {
                return _buildRoute(const PendingApprovalScreen(), settings);
              }
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(const LoginScreen(), settings);
          case AppRoutes.register:
            if (isLoggedIn) {
              if (!isStaff && !isApproved) {
                return _buildRoute(const PendingApprovalScreen(), settings);
              }
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(const RegisterScreen(), settings);
          case AppRoutes.pendingApproval:
            return _buildRoute(const PendingApprovalScreen(), settings);
          case AppRoutes.home:
            return _buildRoute(const HomeScreen(), settings);
          case AppRoutes.companyProducts:
            final brand = settings.arguments as String?;
            if (brand == null || brand.isEmpty) {
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(CompanyProductsScreen(brand: brand), settings);
          case AppRoutes.productDetail:
            final product = settings.arguments as Product?;
            if (product == null) {
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(ProductDetailScreen(product: product), settings);
          case AppRoutes.cart:
            return _buildRoute(const CartScreen(), settings);
          case AppRoutes.orderHistory:
            return _buildRoute(const OrderHistoryScreen(), settings);
          case AppRoutes.orderDetail:
            final order = settings.arguments as Order?;
            if (order == null) {
              return _buildRoute(const OrderHistoryScreen(), settings);
            }
            return _buildRoute(OrderDetailScreen(order: order), settings);
          case AppRoutes.profile:
            return _buildRoute(const ProfileScreen(), settings);
          case AppRoutes.ledgerReport:
            return _buildRoute(const LedgerReportScreen(), settings);
          case AppRoutes.adminDashboard:
            return _buildRoute(const AdminDashboard(), settings);
          case AppRoutes.manageProducts:
            return _buildRoute(const ManageProductsScreen(), settings);
          case AppRoutes.addEditProduct:
            return _buildRoute(const AddEditProductScreen(), settings);
          case AppRoutes.manageOrders:
            return _buildRoute(const ManageOrdersScreen(), settings);
          case AppRoutes.createDeliveryMemo:
            final order = settings.arguments as Order?;
            if (order == null) {
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(CreateDeliveryMemoScreen(order: order), settings);
          case AppRoutes.stockStatus:
            return _buildRoute(const StockStatusScreen(), settings);
          case AppRoutes.customerDirectory:
            return _buildRoute(const CustomerDirectoryScreen(), settings);
          case AppRoutes.allBalances:
            return _buildRoute(const AllBalancesScreen(), settings);
          case AppRoutes.manageBanners:
            return _buildRoute(const ManageBannersScreen(), settings);
          case AppRoutes.salesReports:
            return _buildRoute(const SalesReportsScreen(), settings);
          case AppRoutes.manageBroadcasts:
            return _buildRoute(const ManageBroadcastsScreen(), settings);
          case AppRoutes.adminEmployees:
            return _buildRoute(const ManageEmployeesScreen(), settings);
          case AppRoutes.employeePermissions:
            final employee = settings.arguments as UserModel?;
            if (employee == null) {
              return _buildRoute(const HomeScreen(), settings);
            }
            return _buildRoute(EmployeePermissionsScreen(employee: employee), settings);
          case AppRoutes.employeeTracking:
            return _buildRoute(const EmployeeTrackingScreen(), settings);
          case AppRoutes.notifications:
            return _buildRoute(const NotificationsScreen(), settings);
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
