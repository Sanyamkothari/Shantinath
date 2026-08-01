import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/delivery_memo.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/user_model.dart';

/// Handles creation and voiding of delivery memos. All operations that touch
/// both the memo and the source order run inside a Firestore transaction so
/// the number allocation, the memo write, and the order's delivered quantities
/// can never drift out of sync.
class DeliveryMemoService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _memosRef => _db.collection('delivery_memos');
  CollectionReference get _ordersRef => _db.collection('orders');
  CollectionReference get _countersRef => _db.collection('counters');

  static final DeliveryMemoService _instance =
      DeliveryMemoService._internal();
  factory DeliveryMemoService() => _instance;
  DeliveryMemoService._internal();

  /// Indian financial year label for [date], e.g. "2026-27" (April–March).
  static String financialYear(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    final endYY = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return '$startYear-$endYY';
  }

  /// Creates a delivery memo from [order] for the given [lines] (each carrying
  /// the quantity delivered in this memo), advancing the order's delivered
  /// quantities and status atomically. Returns the persisted [DeliveryMemo].
  Future<DeliveryMemo> createFromOrder({
    required Order order,
    required UserModel? party,
    required List<DeliveryMemoLine> lines,
    required bool showPrices,
    String vehicleNo = '',
    String transporter = '',
    String driverName = '',
    String notes = '',
    required UserModel createdBy,
  }) async {
    if (lines.isEmpty || lines.every((l) => l.quantity <= 0)) {
      throw Exception('Add at least one item with a delivery quantity.');
    }

    final now = DateTime.now();
    final fy = financialYear(now);
    final counterRef = _countersRef.doc('delivery_memos_$fy');
    final orderRef = _ordersRef.doc(order.id);
    final memoRef = _memosRef.doc();

    final memo = await _db.runTransaction<DeliveryMemo>((txn) async {
      // ---- READS (all reads must precede writes in a transaction) ----
      final counterSnap = await txn.get(counterRef);
      final orderSnap = await txn.get(orderRef);

      if (!orderSnap.exists) {
        throw Exception('Order no longer exists.');
      }

      final currentOrder =
          Order.fromJson(orderSnap.data() as Map<String, dynamic>);

      // Validate + apply delivered quantities against the LIVE order.
      final updatedItems = currentOrder.items.map((item) {
        final line = lines.firstWhere(
          (l) => l.productId == item.product.id,
          orElse: () => const DeliveryMemoLine(
              productId: '', productName: '', quantity: 0),
        );
        if (line.quantity <= 0) return item;

        final remaining = item.pendingQuantity;
        if (line.quantity > remaining) {
          throw Exception(
              'Cannot deliver ${line.quantity} of "${item.product.name}" — only $remaining pending.');
        }
        return item.copyWith(
          deliveredQuantity: item.deliveredQuantity + line.quantity,
        );
      }).toList();

      final newSeq =
          ((counterSnap.data() as Map<String, dynamic>?)?['seq'] as int? ?? 0) +
              1;
      final memoNumber = 'DC/$fy/${newSeq.toString().padLeft(4, '0')}';

      final updatedOrder = currentOrder.copyWith(
        items: updatedItems,
        lastModifiedById: createdBy.id,
        lastModifiedByName: createdBy.name,
      );
      final computedStatus = updatedOrder.getComputedStatus();

      final memo = DeliveryMemo(
        id: memoRef.id,
        memoNumber: memoNumber,
        orderId: order.id,
        customerId: currentOrder.customerId,
        customerName: currentOrder.customerName,
        customerPhone: currentOrder.customerPhone,
        customerVillage: currentOrder.customerVillage,
        customerFirm: party?.firmName ?? '',
        customerGst: party?.gstNo ?? '',
        customerSeedLicence: party?.seedLicenceNumber ?? '',
        customerFertLicence: party?.fertilizerLicenceNumber ?? '',
        sellerName: AppConstants.sellerName,
        sellerAddress: AppConstants.sellerAddress,
        sellerPhone: AppConstants.sellerPhone,
        sellerGst: AppConstants.sellerGstNo,
        sellerSeedLicence: AppConstants.sellerSeedLicence,
        sellerFertLicence: AppConstants.sellerFertilizerLicence,
        sellerPesticideLicence: AppConstants.sellerPesticideLicence,
        lines: lines.where((l) => l.quantity > 0).toList(),
        showPrices: showPrices,
        vehicleNo: vehicleNo.trim(),
        transporter: transporter.trim(),
        driverName: driverName.trim(),
        notes: notes.trim(),
        createdAt: now,
        createdById: createdBy.id,
        createdByName: createdBy.name,
      );

      // ---- WRITES ----
      txn.set(counterRef, {
        'seq': newSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      txn.set(memoRef, memo.toJson());

      txn.update(orderRef, {
        'items': updatedItems.map((i) => i.toJson()).toList(),
        'status': computedStatus.name,
        'lastModifiedById': createdBy.id,
        'lastModifiedByName': createdBy.name,
      });

      return memo;
    });

    return memo;
  }

  /// Voids [memo]: reverses the delivered quantities on the source order and
  /// marks the memo cancelled (its number is retained, never reused).
  Future<void> voidMemo({
    required DeliveryMemo memo,
    required UserModel voidedBy,
  }) async {
    if (memo.cancelled) {
      throw Exception('This memo is already cancelled.');
    }

    final memoRef = _memosRef.doc(memo.id);
    final orderRef = _ordersRef.doc(memo.orderId);

    await _db.runTransaction((txn) async {
      final memoSnap = await txn.get(memoRef);
      final orderSnap = await txn.get(orderRef);

      if (!memoSnap.exists) throw Exception('Memo no longer exists.');
      final liveMemo =
          DeliveryMemo.fromJson(memoSnap.data() as Map<String, dynamic>);
      if (liveMemo.cancelled) {
        throw Exception('This memo is already cancelled.');
      }

      if (orderSnap.exists) {
        final currentOrder =
            Order.fromJson(orderSnap.data() as Map<String, dynamic>);
        final updatedItems = currentOrder.items.map((item) {
          final line = liveMemo.lines.firstWhere(
            (l) => l.productId == item.product.id,
            orElse: () => const DeliveryMemoLine(
                productId: '', productName: '', quantity: 0),
          );
          if (line.quantity <= 0) return item;
          final reversed = (item.deliveredQuantity - line.quantity)
              .clamp(0, item.quantity);
          return item.copyWith(deliveredQuantity: reversed);
        }).toList();

        final updatedOrder = currentOrder.copyWith(items: updatedItems);

        txn.update(orderRef, {
          'items': updatedItems.map((i) => i.toJson()).toList(),
          'status': updatedOrder.getComputedStatus().name,
          'lastModifiedById': voidedBy.id,
          'lastModifiedByName': voidedBy.name,
        });
      }

      txn.update(memoRef, {
        'cancelled': true,
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelledByName': voidedBy.name,
      });
    });
  }

  /// All memos for a given order, newest first.
  Future<List<DeliveryMemo>> getMemosForOrder(String orderId) async {
    final snap = await _memosRef
        .where('orderId', isEqualTo: orderId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs
        .map((d) => DeliveryMemo.fromJson(d.data() as Map<String, dynamic>))
        .toList();
  }
}
