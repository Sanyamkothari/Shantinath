import 'package:shantinath_agro/utils/error_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shantinath_agro/models/broadcast_message.dart';
import 'package:shantinath_agro/services/broadcast_service.dart';

/// Provider for managing state of broadcast announcements and notifications.
class BroadcastProvider extends ChangeNotifier {
  final BroadcastService _broadcastService = BroadcastService();
  
  List<BroadcastMessage> _broadcasts = [];
  bool _isLoading = false;
  String? _errorMessage;
  
  DateTime? _lastViewedTime;
  static const String _lastViewedKey = 'notifications_last_viewed_time';

  List<BroadcastMessage> get broadcasts => List.unmodifiable(_broadcasts);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  BroadcastProvider() {
    _loadLastViewedTime();
    Future.microtask(() => loadBroadcasts());
  }

  /// Computes number of notifications created after the user's last notification list visit.
  int get unreadCount {
    if (_broadcasts.isEmpty) return 0;
    if (_lastViewedTime == null) return _broadcasts.length;
    return _broadcasts.where((b) => b.createdAt.isAfter(_lastViewedTime!)).length;
  }

  /// Load last read timestamp from local disk storage.
  Future<void> _loadLastViewedTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_lastViewedKey);
      if (timeStr != null) {
        _lastViewedTime = DateTime.parse(timeStr);
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Marks all current announcements as read and resets the unread badge count.
  Future<void> markAllAsRead() async {
    _lastViewedTime = DateTime.now();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastViewedKey, _lastViewedTime!.toIso8601String());
    } catch (_) {}
  }

  /// Fetch all broadcasts from database.
  Future<void> loadBroadcasts() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _broadcasts = await _broadcastService.getAllBroadcasts();
    } catch (e) {
      _errorMessage = friendlyError(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Publish a new broadcast announcement.
  Future<void> addBroadcast(BroadcastMessage message) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _broadcastService.addBroadcast(message);
      await loadBroadcasts();
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete a past broadcast.
  Future<void> deleteBroadcast(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _broadcastService.deleteBroadcast(id);
      await loadBroadcasts();
    } catch (e) {
      _errorMessage = friendlyError(e);
      _isLoading = false;
      notifyListeners();
    }
  }
}
