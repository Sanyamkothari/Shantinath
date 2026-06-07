import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/user_model.dart';

/// Authentication service backed by Firebase Firestore.
/// Handles admin login and customer registration/login via Firestore.
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _usersRef => _db.collection('users');

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Login with phone number and password.
  /// For admin: verifies against [AppConstants.adminPhone] and [AppConstants.adminPassword].
  /// For customers: checks if the phone is registered in Firestore.
  /// Returns [UserModel] on success, throws [Exception] on failure.
  Future<UserModel> login(String phone, String password) async {
    final trimmedPhone = phone.trim();
    final trimmedPassword = password.trim();

    if (trimmedPhone.isEmpty) {
      throw Exception('Phone number is required');
    }

    // Admin login
    if (trimmedPhone == AppConstants.adminPhone) {
      if (trimmedPassword.isEmpty) {
        throw Exception('Password is required for Admin');
      }
      if (trimmedPassword == AppConstants.adminPassword) {
        return UserModel(
          id: 'admin_001',
          name: 'Shantinath Admin',
          phone: AppConstants.adminPhone,
          village: 'Head Office',
          role: UserRole.admin,
        );
      } else {
        throw Exception('Invalid admin password');
      }
    }

    // Customer login — verify phone exists in Firestore
    final doc = await _usersRef.doc(trimmedPhone).get();
    if (!doc.exists) {
      throw Exception('No account found with this phone number. Please register first.');
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
    if (id == 'admin_001') {
      return UserModel(
        id: 'admin_001',
        name: 'Shantinath Admin',
        phone: AppConstants.adminPhone,
        village: 'Head Office',
        role: UserRole.admin,
      );
    }
    final doc = await _usersRef.doc(id).get();
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
