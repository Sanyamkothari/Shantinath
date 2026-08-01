class AppPermissions {
  AppPermissions._();

  static const String browseCatalog = 'browseCatalog';
  static const String placeOwnOrder = 'placeOwnOrder';
  static const String viewOwnOrders = 'viewOwnOrders';
  static const String viewOwnLedger = 'viewOwnLedger';
  static const String placeOrderForRetailer = 'placeOrderForRetailer';
  static const String manageOrders = 'manageOrders';
  static const String createDeliveryMemo = 'createDeliveryMemo';
  static const String viewCustomerDirectory = 'viewCustomerDirectory';
  static const String viewCustomerBalances = 'viewCustomerBalances';
  static const String viewSalesReports = 'viewSalesReports';
  static const String manageProducts = 'manageProducts';
  static const String manageBanners = 'manageBanners';
  static const String manageBroadcasts = 'manageBroadcasts';
  static const String approveUsers = 'approveUsers';
  static const String manageEmployees = 'manageEmployees';
  static const String managePermissions = 'managePermissions';
  static const String viewAuditLogs = 'viewAuditLogs';

  static const Map<String, String> labelsEn = {
    browseCatalog: 'View product catalog',
    placeOwnOrder: 'Place order for self',
    viewOwnOrders: 'Own order history',
    viewOwnLedger: 'Own balance/ledger',
    placeOrderForRetailer: 'Order on behalf of any retailer',
    manageOrders: 'View/update/cancel any order',
    createDeliveryMemo: 'Create & print delivery memos',
    viewCustomerDirectory: 'Retailer directory + order history',
    viewCustomerBalances: "See retailers' credit/debit",
    viewSalesReports: 'Revenue analytics',
    manageProducts: 'Add/edit/delete products & pricing',
    manageBanners: 'Promo banners',
    manageBroadcasts: 'Announcements',
    approveUsers: 'Approve registrations',
    manageEmployees: 'Add/remove staff',
    managePermissions: 'Grant/revoke permissions & roles (master key)',
    viewAuditLogs: 'Employee tracking',
  };

  static const Map<String, String> labelsMr = {
    browseCatalog: 'उत्पादन कॅटलॉग पहा',
    placeOwnOrder: 'स्वतःसाठी ऑर्डर नोंदवा',
    viewOwnOrders: 'स्वतःचा ऑर्डर इतिहास',
    viewOwnLedger: 'स्वतःचे खाते/लेजर',
    placeOrderForRetailer: 'कोणत्याही किरकोळ विक्रेत्याच्या वतीने ऑर्डर नोंदवा',
    manageOrders: 'कोणतीही ऑर्डर पहा/अपडेट/रद्द करा',
    createDeliveryMemo: 'डिलिव्हरी मेमो तयार करा व प्रिंट करा',
    viewCustomerDirectory: 'किरकोळ विक्रेता निर्देशिका + ऑर्डर इतिहास',
    viewCustomerBalances: 'किरकोळ विक्रेत्यांची क्रेडिट/डेबिट शिल्लक पहा',
    viewSalesReports: 'महसूल विश्लेषण',
    manageProducts: 'उत्पादने आणि किंमती जोडा/सुधारा/हटवा',
    manageBanners: 'जाहिरात बॅनर्स व्यवस्थापित करा',
    manageBroadcasts: 'घोषणा / ब्रॉडकास्ट व्यवस्थापित करा',
    approveUsers: 'नोंदणी मंजूर करा',
    manageEmployees: 'कर्मचारी जोडा/काढून टाका',
    managePermissions: 'परवानग्या आणि भूमिका मंजूर/रद्द करा (मास्टर की)',
    viewAuditLogs: 'कर्मचारी कृती ट्रॅकिंग',
  };

  static String getLabel(String permissionKey, bool isMarathi) {
    if (isMarathi) {
      return labelsMr[permissionKey] ?? permissionKey;
    }
    return labelsEn[permissionKey] ?? permissionKey;
  }

  static const List<String> customerPreset = [
    browseCatalog,
    placeOwnOrder,
    viewOwnOrders,
    viewOwnLedger,
  ];

  static const List<String> orderStaffPreset = [
    browseCatalog,
    viewOwnOrders,
    viewOwnLedger,
    placeOrderForRetailer,
    manageOrders,
    createDeliveryMemo,
    viewCustomerDirectory,
  ];

  static const List<String> salesRepPreset = [
    ...orderStaffPreset,
    viewCustomerBalances,
    viewSalesReports,
  ];

  static const List<String> allPermissions = [
    browseCatalog,
    placeOwnOrder,
    viewOwnOrders,
    viewOwnLedger,
    placeOrderForRetailer,
    manageOrders,
    createDeliveryMemo,
    viewCustomerDirectory,
    viewCustomerBalances,
    viewSalesReports,
    manageProducts,
    manageBanners,
    manageBroadcasts,
    approveUsers,
    manageEmployees,
    managePermissions,
    viewAuditLogs,
  ];
}
