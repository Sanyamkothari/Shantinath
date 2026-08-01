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
  static const String pendingApproval = '/pending-approval';
  static const String home = '/home';
  static const String companyProducts = '/company-products';
  static const String productDetail = '/product-detail';
  static const String cart = '/cart';
  static const String orderHistory = '/order-history';
  static const String orderDetail = '/order-detail';
  static const String profile = '/profile';
  static const String ledgerReport = '/ledger-report';
  static const String adminDashboard = '/admin/dashboard';
  static const String manageProducts = '/admin/manage-products';
  static const String addEditProduct = '/admin/add-edit-product';
  static const String manageOrders = '/admin/manage-orders';
  static const String createDeliveryMemo = '/admin/create-delivery-memo';
  static const String customerDirectory = '/admin/customer-directory';
  static const String allBalances = '/admin/all-balances';
  static const String stockStatus = '/admin/stock-status';
  static const String manageBanners = '/admin/manage-banners';
  static const String salesReports = '/admin/sales-reports';
  static const String manageBroadcasts = '/admin/manage-broadcasts';
  static const String adminEmployees = '/admin/employees';
  static const String employeePermissions = '/admin/employee-permissions';
  static const String employeeTracking = '/admin/employee-tracking';
  static const String notifications = '/notifications';
}

