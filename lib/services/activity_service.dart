import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  }) async {
    try {
      UserModel? activeActor = actor;
      if (activeActor == null) {
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
        'actorId': activeActor?.phone ?? 'system',
        'actorName': activeActor?.name ?? 'System/Visitor',
        'actorRole': activeActor?.role.name ?? 'visitor',
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
}
