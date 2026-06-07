/// Named route constants for the entire application.
///
/// Usage:
/// ```dart
/// Navigator.pushNamed(context, AppRoutes.productDetail, arguments: productId);
/// ```
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String productDetail = '/product-detail';
  static const String cart = '/cart';
  static const String orderHistory = '/order-history';
  static const String orderDetail = '/order-detail';
  static const String profile = '/profile';
  static const String adminDashboard = '/admin/dashboard';
  static const String manageProducts = '/admin/manage-products';
  static const String addEditProduct = '/admin/add-edit-product';
  static const String manageOrders = '/admin/manage-orders';
  static const String customerDirectory = '/admin/customer-directory';
}
