/// A single line on a delivery memo — one product and the quantity being
/// delivered in THIS memo (which may be a partial fulfilment of the order).
class DeliveryMemoLine {
  final String productId;
  final String productName;
  final String packSize;
  final String batchLot; // manual, optional (regulatory)
  final int quantity; // quantity delivered in this memo
  final double rate; // unit price snapshot at memo time

  const DeliveryMemoLine({
    required this.productId,
    required this.productName,
    this.packSize = '',
    this.batchLot = '',
    required this.quantity,
    this.rate = 0.0,
  });

  double get amount => rate * quantity;

  factory DeliveryMemoLine.fromJson(Map<String, dynamic> json) {
    return DeliveryMemoLine(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      packSize: json['packSize'] as String? ?? '',
      batchLot: json['batchLot'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'packSize': packSize,
        'batchLot': batchLot,
        'quantity': quantity,
        'rate': rate,
      };
}

/// A delivery memo (delivery challan) generated from an order. It is a legal
/// record, so party/seller details and prices are **snapshotted** at creation
/// time and never re-derived from live data.
class DeliveryMemo {
  final String id;
  final String memoNumber; // e.g. "DC/2026-27/0042"
  final String orderId;

  // Party (customer) snapshot.
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerVillage;
  final String customerFirm;
  final String customerGst;
  final String customerSeedLicence;
  final String customerFertLicence;

  // Seller snapshot.
  final String sellerName;
  final String sellerAddress;
  final String sellerPhone;
  final String sellerGst;
  final String sellerSeedLicence;
  final String sellerFertLicence;
  final String sellerPesticideLicence;

  final List<DeliveryMemoLine> lines;
  final bool showPrices;

  final String vehicleNo;
  final String transporter;
  final String driverName;
  final String notes;

  final DateTime createdAt;
  final String createdById;
  final String createdByName;

  // Void / cancellation.
  final bool cancelled;
  final DateTime? cancelledAt;
  final String cancelledByName;

  const DeliveryMemo({
    required this.id,
    required this.memoNumber,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    this.customerPhone = '',
    this.customerVillage = '',
    this.customerFirm = '',
    this.customerGst = '',
    this.customerSeedLicence = '',
    this.customerFertLicence = '',
    required this.sellerName,
    this.sellerAddress = '',
    this.sellerPhone = '',
    this.sellerGst = '',
    this.sellerSeedLicence = '',
    this.sellerFertLicence = '',
    this.sellerPesticideLicence = '',
    required this.lines,
    this.showPrices = false,
    this.vehicleNo = '',
    this.transporter = '',
    this.driverName = '',
    this.notes = '',
    required this.createdAt,
    this.createdById = '',
    this.createdByName = '',
    this.cancelled = false,
    this.cancelledAt,
    this.cancelledByName = '',
  });

  int get totalQuantity => lines.fold(0, (sum, l) => sum + l.quantity);

  double get totalAmount => lines.fold(0.0, (sum, l) => sum + l.amount);

  factory DeliveryMemo.fromJson(Map<String, dynamic> json) {
    return DeliveryMemo(
      id: json['id'] as String? ?? '',
      memoNumber: json['memoNumber'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      customerId: json['customerId'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerVillage: json['customerVillage'] as String? ?? '',
      customerFirm: json['customerFirm'] as String? ?? '',
      customerGst: json['customerGst'] as String? ?? '',
      customerSeedLicence: json['customerSeedLicence'] as String? ?? '',
      customerFertLicence: json['customerFertLicence'] as String? ?? '',
      sellerName: json['sellerName'] as String? ?? '',
      sellerAddress: json['sellerAddress'] as String? ?? '',
      sellerPhone: json['sellerPhone'] as String? ?? '',
      sellerGst: json['sellerGst'] as String? ?? '',
      sellerSeedLicence: json['sellerSeedLicence'] as String? ?? '',
      sellerFertLicence: json['sellerFertLicence'] as String? ?? '',
      sellerPesticideLicence: json['sellerPesticideLicence'] as String? ?? '',
      lines: (json['lines'] as List<dynamic>? ?? [])
          .map((e) => DeliveryMemoLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      showPrices: json['showPrices'] as bool? ?? false,
      vehicleNo: json['vehicleNo'] as String? ?? '',
      transporter: json['transporter'] as String? ?? '',
      driverName: json['driverName'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.parse(
          json['createdAt'] as String? ?? DateTime.now().toIso8601String()),
      createdById: json['createdById'] as String? ?? '',
      createdByName: json['createdByName'] as String? ?? '',
      cancelled: json['cancelled'] as bool? ?? false,
      cancelledAt: json['cancelledAt'] != null
          ? DateTime.tryParse(json['cancelledAt'] as String)
          : null,
      cancelledByName: json['cancelledByName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'memoNumber': memoNumber,
        'orderId': orderId,
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerVillage': customerVillage,
        'customerFirm': customerFirm,
        'customerGst': customerGst,
        'customerSeedLicence': customerSeedLicence,
        'customerFertLicence': customerFertLicence,
        'sellerName': sellerName,
        'sellerAddress': sellerAddress,
        'sellerPhone': sellerPhone,
        'sellerGst': sellerGst,
        'sellerSeedLicence': sellerSeedLicence,
        'sellerFertLicence': sellerFertLicence,
        'sellerPesticideLicence': sellerPesticideLicence,
        'lines': lines.map((l) => l.toJson()).toList(),
        'showPrices': showPrices,
        'vehicleNo': vehicleNo,
        'transporter': transporter,
        'driverName': driverName,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'createdById': createdById,
        'createdByName': createdByName,
        'cancelled': cancelled,
        'cancelledAt': cancelledAt?.toIso8601String(),
        'cancelledByName': cancelledByName,
      };
}
