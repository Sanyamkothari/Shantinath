import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/services/auth_service.dart';

/// ChangeNotifier provider for authentication state.
/// Wraps [AuthService] and exposes reactive state for the UI.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  static const String _phonePrefKey = 'user_phone';

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  /// The currently logged-in user, or null if not authenticated.
  UserModel? get currentUser => _currentUser;

  /// Whether an authentication operation is in progress.
  bool get isLoading => _isLoading;

  /// The most recent error message, if any.
  String? get errorMessage => _errorMessage;

  /// Whether a user is currently logged in.
  bool get isLoggedIn => _currentUser != null;

  /// Whether the current user has admin privileges.
  bool get isAdmin =>
      _currentUser != null && _currentUser!.role == UserRole.admin;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Try to restore user session from SharedPreferences.
  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(_phonePrefKey);
      if (phone == null || phone.isEmpty) return false;

      // Restoring Admin session
      if (phone == AppConstants.adminPhone) {
        _currentUser = const UserModel(
          id: 'admin_001',
          name: 'Shantinath Admin',
          phone: AppConstants.adminPhone,
          village: 'Head Office',
          role: UserRole.admin,
        );
        notifyListeners();
        return true;
      }

      // Restoring Customer session
      final user = await _authService.getUserByPhone(phone);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Auto login failed: $e');
      return false;
    }
  }

  /// Login with [phone] and [password].
  /// Sets [currentUser] on success, sets [errorMessage] on failure.
  /// Returns true on success, false on failure.
  Future<bool> login(String phone, String password) async {
    _setLoading(true);
    _clearError();

    try {
      _currentUser = await _authService.login(phone, password);
      if (_currentUser != null) {
        await _saveSession(_currentUser!.phone);
      }
      _setLoading(false);
      return true;
    } on Exception catch (e) {
      _setError(_extractMessage(e));
      _setLoading(false);
      return false;
    }
  }

  /// Register a new customer with [name], [phone], and [village].
  /// Sets [currentUser] on success (auto-login after registration).
  /// Returns true on success, false on failure.
  Future<bool> register({
    required String name,
    required String phone,
    required String village,
    String firmName = '',
    String seedLicenceNumber = '',
    String fertilizerLicenceNumber = '',
    String proprietorName = '',
    String gstNo = '',
    String secondLicenceNumber = '',
    String taluka = '',
    String district = '',
    String khatIdNo = '',
    String customerType = '',
  }) async {
    _setLoading(true);
    _clearError();

    try {
      _currentUser = await _authService.registerCustomer(
        name: name,
        phone: phone,
        village: village,
        firmName: firmName,
        seedLicenceNumber: seedLicenceNumber,
        fertilizerLicenceNumber: fertilizerLicenceNumber,
        proprietorName: proprietorName,
        gstNo: gstNo,
        secondLicenceNumber: secondLicenceNumber,
        taluka: taluka,
        district: district,
        khatIdNo: khatIdNo,
        customerType: customerType,
      );
      if (_currentUser != null) {
        await _saveSession(_currentUser!.phone);
      }
      _setLoading(false);
      return true;
    } on Exception catch (e) {
      _setError(_extractMessage(e));
      _setLoading(false);
      return false;
    }
  }

  /// Logout the current user.
  void logout() {
    _currentUser = null;
    _clearSession();
    _clearError();
    notifyListeners();
  }

  /// Clear any existing error message.
  void clearError() {
    _clearError();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Save user session details in SharedPreferences.
  Future<void> _saveSession(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_phonePrefKey, phone);
    } catch (e) {
      debugPrint('Failed to save session: $e');
    }
  }

  /// Clear user session details from SharedPreferences.
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_phonePrefKey);
    } catch (e) {
      debugPrint('Failed to clear session: $e');
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Extract a clean error message from an exception.
  String _extractMessage(Exception e) {
    final raw = e.toString();
    // Remove 'Exception: ' prefix if present
    if (raw.startsWith('Exception: ')) {
      return raw.substring(11);
    }
    return raw;
  }
}
