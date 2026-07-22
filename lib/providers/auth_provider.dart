import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/user_model.dart';
import 'package:shantinath_agro/services/auth_service.dart';
import 'package:shantinath_agro/services/activity_service.dart';

/// ChangeNotifier provider for authentication state.
/// Wraps [AuthService] and exposes reactive state for the UI.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  static const String _phonePrefKey = 'user_phone';

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  String? _verificationId;
  bool _otpSent = false;
  String? _otpVerifiedPhone;

  StreamSubscription<DocumentSnapshot>? _userSubscription;

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

  /// Whether OTP was successfully dispatched to the device.
  bool get otpSent => _otpSent;

  /// Whether [phone] has completed OTP verification during this session.
  /// Used to gate registration so an account can only be created for a phone
  /// number whose ownership was proven via OTP.
  bool isPhoneVerified(String phone) => _otpVerifiedPhone == phone.trim();

  /// Whether the current user has admin privileges.
  bool get isAdmin =>
      _currentUser != null && _currentUser!.role == UserRole.admin;

  /// Whether the current user is an employee.
  bool get isEmployee =>
      _currentUser != null && _currentUser!.role == UserRole.employee;

  /// Whether the current user is staff (admin or employee).
  bool get isStaff =>
      _currentUser != null && _currentUser!.isStaff;

  /// Checks if the current user has a specific permission.
  bool can(String key) =>
      _currentUser != null && _currentUser!.hasPermission(key);

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Reset the OTP status variables.
  void resetOtpStatus() {
    _otpSent = false;
    _verificationId = null;
    notifyListeners();
  }

  /// Try to restore user session.
  Future<bool> tryAutoLogin() async {
    try {
      if (AppConstants.useMockOtp) {
        final prefs = await SharedPreferences.getInstance();
        final phone = prefs.getString(_phonePrefKey);
        if (phone == null || phone.isEmpty) return false;

        final user = await _authService.getUserByPhone(phone);
        if (user != null) {
          _currentUser = user;
          _listenToCurrentUser();
          notifyListeners();
          return true;
        }
        return false;
      } else {
        // Real Firebase Auth state check. We sign in with a custom token whose
        // UID is the bare 10-digit phone number, so derive the phone from the
        // UID (falling back to the phoneNumber claim for older sessions).
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser == null) return false;

        var phone = firebaseUser.uid;
        if (phone.isEmpty) {
          phone = firebaseUser.phoneNumber ?? '';
        }
        if (phone.isEmpty) return false;

        // Strip country code (+91) to match the domestic phone format in the DB.
        if (phone.startsWith('+91')) {
          phone = phone.substring(3);
        }

        final user = await _authService.getUserByPhone(phone);
        if (user != null) {
          _currentUser = user;
          _listenToCurrentUser();
          notifyListeners();
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('Auto login failed: $e');
      return false;
    }
  }

  /// Send OTP code to the specified [phone] number.
  Future<bool> sendOtp(String phone) async {
    _setLoading(true);
    _clearError();

    final completer = Completer<bool>();

    await _authService.sendOtp(
      phone: phone,
      onCodeSent: (verificationId) {
        _verificationId = verificationId;
        _otpSent = true;
        _setLoading(false);
        completer.complete(true);
      },
      onError: (error) {
        _setError(error);
        _otpSent = false;
        _setLoading(false);
        completer.complete(false);
      },
    );

    return completer.future;
  }

  /// Verify the OTP code [smsCode] and logs in.
  /// Sets [currentUser] on success.
  /// Returns true on success, false on verification/auth failure.
  /// Note: Throws nothing. If user profile doesn't exist, successful OTP will still return true,
  /// but [currentUser] will remain null, signaling to UI to redirect to Registration page.
  Future<bool> verifyOtpAndLogin(String phone, String smsCode) async {
    _setLoading(true);
    _clearError();

    if (_verificationId == null) {
      _setError('Verification session expired. Please request a new OTP.');
      _setLoading(false);
      return false;
    }

    try {
      _currentUser = await _authService.verifyOtpAndLogin(
        phone: phone,
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      // OTP was valid (no exception thrown) — remember this phone is verified.
      _otpVerifiedPhone = phone.trim();

      if (_currentUser != null) {
        if (AppConstants.useMockOtp) {
          await _saveSession(_currentUser!.phone);
        }
        _listenToCurrentUser();
        // Log login action
        ActivityService.log(
          action: 'login',
          summary: '${_currentUser!.name} (${_currentUser!.roleText}) logged in successfully.',
          actor: _currentUser,
        );
      }
      _setLoading(false);
      return true;
    } catch (e) {
      final msg = _extractMessage(e);
      if (msg == 'USER_NOT_REGISTERED') {
        // OTP itself was valid; only the profile is missing. Mark the phone as
        // verified so the registration screen can proceed to create the account.
        _otpVerifiedPhone = phone.trim();
        _setLoading(false);
        // OTP was valid, but user document doesn't exist yet. We return success (true)
        // to verify OTP passed, but keep currentUser null so screen can route to register.
        return true;
      }
      _setError(msg);
      _setLoading(false);
      return false;
    }
  }

  /// Complete registration for a newly verified user.
  /// Automatically sets the logged-in [currentUser].
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
        if (AppConstants.useMockOtp) {
          await _saveSession(_currentUser!.phone);
        }
        _listenToCurrentUser();
      }
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_extractMessage(e));
      _setLoading(false);
      return false;
    }
  }

  /// Logout the current user.
  Future<void> logout() async {
    if (_currentUser != null) {
      ActivityService.log(
        action: 'logout',
        summary: '${_currentUser!.name} (${_currentUser!.roleText}) logged out.',
        actor: _currentUser,
      );
    }
    _currentUser = null;
    await _userSubscription?.cancel();
    _userSubscription = null;
    _otpVerifiedPhone = null;
    resetOtpStatus();
    _clearError();
    if (AppConstants.useMockOtp) {
      await _clearSession();
    } else {
      await FirebaseAuth.instance.signOut();
    }
    notifyListeners();
  }

  /// Start listening reactively to changes on the current user's profile
  void _listenToCurrentUser() {
    _userSubscription?.cancel();
    if (_currentUser == null) return;

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.phone)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          final updatedUser = UserModel.fromJson(snapshot.data() as Map<String, dynamic>);
          _currentUser = updatedUser;
          notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('Error listening to user changes: $error');
      },
    );
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  /// Refresh the current user's profile details.
  Future<void> refreshCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final user = await _authService.getUserByPhone(_currentUser!.phone);
      if (user != null) {
        _currentUser = user;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh user: $e');
    }
  }

  /// Update the FCM token for the currently authenticated user.
  Future<void> updateFcmToken(String token) async {
    if (_currentUser == null) return;
    try {
      await _authService.updateFcmToken(_currentUser!.phone, token);
      _currentUser = _currentUser!.copyWith(fcmToken: token);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating FCM token in provider: $e');
    }
  }

  /// Approve or reject a user (Admin action).
  Future<void> approveUser(String phone, bool isApproved) async {
    try {
      await _authService.updateApprovalStatus(phone, isApproved);
    } catch (e) {
      throw Exception('Failed to update user approval: $e');
    }
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

  /// Extract a clean error message from an exception or error.
  String _extractMessage(Object e) {
    final raw = e.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring(11);
    }
    return raw;
  }

  /// Fetch all synced Tally parties for registration lookup.
  Future<List<Map<String, dynamic>>> getTallyParties() async {
    return await _authService.getTallyParties();
  }
}
