import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/user_model.dart';

/// Authentication service backed by Firebase Firestore and Firebase Auth.
/// Handles OTP sending/verification and customer registration/login via Firestore.
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  CollectionReference get _usersRef => _db.collection('users');

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Send OTP to the specified [phone] number.
  /// If [AppConstants.useMockOtp] is true, triggers simulated SMS code dispatch.
  Future<void> sendOtp({
    required String phone,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    final formattedPhone = '+91${phone.trim()}';

    if (AppConstants.useMockOtp) {
      // Mock OTP Dispatch Simulation
      await Future.delayed(const Duration(milliseconds: 800));
      onCodeSent('mock_verification_id_$phone');
      return;
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Can automatically sign in if phone verification is auto-resolved
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(e.message ?? 'Verification failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Verify the OTP [smsCode] and fetch the user profile.
  /// Returns the authenticated [UserModel].
  /// Throws Exception('USER_NOT_REGISTERED') if OTP is valid but user profile does not exist.
  Future<UserModel> verifyOtpAndLogin({
    required String phone,
    required String verificationId,
    required String smsCode,
  }) async {
    final trimmedPhone = phone.trim();

    if (AppConstants.useMockOtp) {
      if (smsCode != '123456') {
        throw Exception('Invalid verification code');
      }
      return await _fetchOrCreateUserSession(trimmedPhone);
    }

    // Real Firebase OTP Verification
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );

    // Sign in to Firebase Auth
    final userCredential = await _auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      throw Exception('Authentication failed');
    }

    return await _fetchOrCreateUserSession(trimmedPhone);
  }

  Future<UserModel> _fetchOrCreateUserSession(String phone) async {
    // Admin check: If phone matches AppConstants.adminPhone, check Firestore or create admin profile
    if (phone == AppConstants.adminPhone) {
      final doc = await _usersRef.doc(phone).get();
      if (!doc.exists) {
        final adminUser = UserModel(
          id: phone,
          name: 'Shantinath Admin',
          phone: phone,
          village: 'Head Office',
          role: UserRole.admin,
        );
        await _usersRef.doc(phone).set(adminUser.toJson());
        return adminUser;
      }
      return UserModel.fromJson(doc.data() as Map<String, dynamic>);
    }

    // Customer login — verify profile exists in Firestore
    final doc = await _usersRef.doc(phone).get();
    if (!doc.exists) {
      throw Exception('USER_NOT_REGISTERED');
    }

    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Failed to load user data');
    }

    return UserModel.fromJson(data);
  }

  /// Register a new customer account in Firestore.
  /// Returns [UserModel] on success, throws [Exception] if phone already registered.
  Future<UserModel> registerCustomer({
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
    final trimmedName = name.trim();
    final trimmedPhone = phone.trim();
    final trimmedVillage = village.trim();
    final trimmedFirmName = firmName.trim();
    final trimmedProprietorName = proprietorName.trim();
    final trimmedTaluka = taluka.trim();
    final trimmedDistrict = district.trim();
    final trimmedCustomerType = customerType.trim();

    if (trimmedName.isEmpty) {
      throw Exception('Name is required');
    }

    if (trimmedPhone.isEmpty || trimmedPhone.length < 10) {
      throw Exception('A valid 10-digit phone number is required');
    }

    if (trimmedProprietorName.isEmpty) {
      throw Exception('Proprietor name is required');
    }

    if (trimmedFirmName.isEmpty) {
      throw Exception('Firm name is required');
    }

    if (trimmedVillage.isEmpty) {
      throw Exception('Village / City name is required');
    }

    if (trimmedTaluka.isEmpty) {
      throw Exception('Taluka is required');
    }

    if (trimmedDistrict.isEmpty) {
      throw Exception('District is required');
    }

    if (trimmedCustomerType.isEmpty) {
      throw Exception('Customer type (Wholesale/Retail) is required');
    }

    // Check for duplicate phone in Firestore
    final doc = await _usersRef.doc(trimmedPhone).get();
    if (doc.exists) {
      throw Exception('An account with this phone number already exists. Please login.');
    }

    final user = UserModel(
      id: trimmedPhone, // Using phone as unique customer ID
      name: trimmedName,
      phone: trimmedPhone,
      village: trimmedVillage,
      role: UserRole.customer,
      firmName: trimmedFirmName,
      seedLicenceNumber: seedLicenceNumber.trim(),
      fertilizerLicenceNumber: fertilizerLicenceNumber.trim(),
      proprietorName: trimmedProprietorName,
      gstNo: gstNo.trim(),
      secondLicenceNumber: secondLicenceNumber.trim(),
      taluka: trimmedTaluka,
      district: trimmedDistrict,
      khatIdNo: khatIdNo.trim(),
      customerType: trimmedCustomerType,
    );

    // Save user to Firestore
    await _usersRef.doc(trimmedPhone).set(user.toJson());
    return user;
  }

  /// Get a user by their phone number. Returns null if not found.
  Future<UserModel?> getUserByPhone(String phone) async {
    final doc = await _usersRef.doc(phone.trim()).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Get a user by their ID. Returns null if not found.
  Future<UserModel?> getUserById(String id) async {
    final queryId = (id == 'admin_001') ? AppConstants.adminPhone : id;
    final doc = await _usersRef.doc(queryId).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Check if a phone number is registered.
  Future<bool> isPhoneRegistered(String phone) async {
    final doc = await _usersRef.doc(phone.trim()).get();
    return doc.exists;
  }
}
