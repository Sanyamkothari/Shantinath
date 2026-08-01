import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shantinath_agro/providers/auth_provider.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;

  /// Initialize Push Notifications (FCM) and request user permissions.
  Future<void> initialize(BuildContext context, AuthProvider authProvider) async {
    if (_initialized) return;

    try {
      // 1. Request permissions (especially required for iOS and Android 13+)
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      debugPrint('User granted notification permission: ${settings.authorizationStatus}');

      // 2. Fetch and register device FCM token
      if (authProvider.isLoggedIn) {
        await _registerFcmToken(authProvider);
      }

      // Listen for token refresh in background
      _fcm.onTokenRefresh.listen((token) async {
        if (authProvider.isLoggedIn) {
          await authProvider.updateFcmToken(token);
        }
      });

      // 3. Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message received: ${message.messageId}');
        
        final notification = message.notification;
        if (notification != null && context.mounted) {
          // Show beautiful in-app floating banner for foreground push alerts
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.title ?? 'Alert',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          notification.body ?? '',
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              action: SnackBarAction(
                label: 'DISMISS',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      });

      // 4. Handle notification tap when app is opened from terminated/background state
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM Notification tapped and opened app: ${message.data}');
        // You can add deep-linking or routing here if needed (e.g., navigating to notifications screen)
      });

      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize FCM: $e');
    }
  }

  /// Fetch token and save it to the current user's profile in Firestore
  Future<void> _registerFcmToken(AuthProvider authProvider) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('Device FCM Token: $token');
        await authProvider.updateFcmToken(token);
      }
    } catch (e) {
      debugPrint('Error getting device FCM token: $e');
    }
  }

  /// Re-check and sync FCM token upon login
  Future<void> syncToken(AuthProvider authProvider) async {
    if (authProvider.isLoggedIn) {
      await _registerFcmToken(authProvider);
    }
  }
}
