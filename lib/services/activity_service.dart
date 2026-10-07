import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shantinath_agro/models/order.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

class ActivityService {
  ActivityService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Uuid _uuid = Uuid();

  /// Logs an activity to the activity_logs collection.
  static Future<void> log({
    required String action,
    String? targetType,
    String? targetId,
    required String summary,
    Map<String, dynamic> metadata = const {},
    UserModel? actor,
    String? actorId,
    String? actorName,
    String? actorRole,
  }) async {
    try {
      UserModel? activeActor = actor;
      // Explicit actor fields skip the profile lookup. actorId must equal the
      // signed-in user's own number (or 'system'), which firestore.rules checks.
      if (activeActor == null && actorId == null) {
        // Fallback for real OTP
        final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
        if (phone != null) {
          var cleanPhone = phone;
          if (cleanPhone.startsWith('+91')) {
            cleanPhone = cleanPhone.substring(3);
          }
          activeActor = await AuthService().getUserByPhone(cleanPhone);
        }
      }

      final logId = 'LOG-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final docRef = _db.collection('activity_logs').doc(logId);

      await docRef.set({
        'id': logId,
        'actorId': actorId ?? activeActor?.phone ?? 'system',
        'actorName': actorName ?? activeActor?.name ?? 'System/Visitor',
        'actorRole': actorRole ?? activeActor?.role.name ?? 'visitor',
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'summary': summary,
        'metadata': metadata,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Fail silently in production
      debugPrint('Failed to write activity log: $e');
    }
  }

  static String _shortId(String orderId) =>
      orderId.length > 8 ? orderId.substring(0, 8) : orderId;

  /// Audit row for a newly placed order. Replaces the former `onOrderCreated`
  /// Cloud Function trigger (the Spark plan has no Cloud Functions).
  static Future<void> logOrderPlaced(Order order) {
    final byStaff = order.placedById.isNotEmpty;
    final actorId =
        byStaff ? order.placedById : order.customerId.replaceFirst('+91', '');
    final actorName = byStaff
        ? order.placedByName
        : (order.customerName.isNotEmpty ? order.customerName : 'Customer');
    final id = _shortId(order.id);
    final amount = order.totalAmount;
    return log(
      action: 'order_placed',
      actorId: actorId,
      actorName: actorName,
      actorRole: byStaff ? 'employee' : 'customer',
      targetType: 'order',
      targetId: order.id,
      summary: byStaff
          ? 'Employee ${order.placedByName} placed order #$id (₹$amount) on behalf of customer ${order.customerName}.'
          : 'Customer ${order.customerName} placed order #$id (₹$amount).',
      metadata: {
        'totalAmount': order.totalAmount,
        'itemCount': order.items.length,
      },
    );
  }

  /// Audit row for a status / items / amount change on an order. Replaces the
  /// former `onOrderUpdated` Cloud Function trigger. Does nothing when none of
  /// those changed.
  static Future<void> logOrderModified({
    required Order before,
    required Order after,
    required String modifiedById,
    required String modifiedByName,
  }) {
    final statusChanged = before.status != after.status;
    final itemsChanged = jsonEncode(before.items.map((i) => i.toJson()).toList()) !=
        jsonEncode(after.items.map((i) => i.toJson()).toList());
    final amountChanged = before.totalAmount != after.totalAmount;
    if (!statusChanged && !itemsChanged && !amountChanged) {
      return Future.value();
    }

    final byStaff = modifiedById.isNotEmpty;
    final actorName = byStaff && modifiedByName.isNotEmpty
        ? modifiedByName
        : 'System / Admin';
    final id = _shortId(after.id);
    final summary = statusChanged
        ? 'Order #$id status changed from ${before.status.name} to ${after.status.name} by $actorName.'
        : 'Order #$id items/quantities updated by $actorName.';

    return log(
      action: 'order_modified',
      actorId: byStaff ? modifiedById : 'system',
      actorName: actorName,
      actorRole: byStaff ? 'staff' : 'admin',
      targetType: 'order',
      targetId: after.id,
      summary: summary,
      metadata: {
        'oldStatus': before.status.name,
        'newStatus': after.status.name,
        'oldAmount': before.totalAmount,
        'newAmount': after.totalAmount,
      },
    );
  }
}
