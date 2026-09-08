import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shantinath_agro/config/constants.dart';
import 'package:shantinath_agro/models/user_model.dart';


/// Authentication service backed by Firebase Firestore and Firebase Auth.
///
/// OTP is handled by MessageCentral VerifyNow (no DLT registration required) via
/// two Cloud Functions that keep the MessageCentral credentials server-side:
///   • sendOtp   → MessageCentral /verification/v3/send   → returns verificationId
///   • verifyOtp → MessageCentral /verification/v3/validateOtp → mints a Firebase
///                 custom token (uid = phone, claim phone_number = `+91<phone>`).
/// The app then signs in with that custom token, which satisfies the Firestore
/// security rules. Customer profiles are stored keyed by the bare 10-digit number.
class AuthService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  CollectionReference get _usersRef => _db.collection('users');

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String get _functionsBaseUrl {
    final projectId = Firebase.app().options.projectId;
    return 'https://${AppConstants.cloudFunctionsRegion}-$projectId.cloudfunctions.net';
  }

  /// Send an OTP to the specified [phone] via the sendOtp Cloud Function
  /// (MessageCentral VerifyNow). If [AppConstants.useMockOtp] is true, triggers
  /// a simulated dispatch.
  ///
  /// [onCodeSent] receives the MessageCentral `verificationId` (needed for
  /// validation). [onError] receives a human-readable failure message.
  ///
  /// With [requireRegistered] the server refuses (without sending an SMS) when
  /// no profile exists for [phone] and [onNotRegistered] is called instead.
  /// This has to be a server-side check: a signed-out client cannot read
  /// `users/{phone}` itself, the security rules deny it.
  Future<void> sendOtp({
    required String phone,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    bool requireRegistered = false,
    void Function()? onNotRegistered,
  }) async {
    final trimmedPhone = phone.trim();

    if (AppConstants.useMockOtp) {
      // Mock OTP Dispatch Simulation
      await Future.delayed(const Duration(milliseconds: 800));
      onCodeSent('mock_verification_id_$trimmedPhone');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/sendOtp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': trimmedPhone,
          if (requireRegistered) 'requireRegistered': true,
        }),
      );

      // Guard: Cloud Functions may return an HTML error page (e.g. 404/500)
      // when the function is not deployed or crashes on startup.
      final body = response.body.trim();
      if (body.startsWith('<') || body.startsWith('<!')) {
        onError('Server error. The OTP service is temporarily unavailable. Please try again later.');
        return;
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode == 200 && data['success'] == true) {
        onCodeSent(data['verificationId'].toString());
      } else if (data['code'] == 'NOT_REGISTERED' && onNotRegistered != null) {
        onNotRegistered();
      } else {
        onError(data['error']?.toString() ?? 'Failed to send OTP.');
      }
    } catch (e) {
      onError('Network error. Please check your connection and try again.');
    }
  }

  /// Verify the OTP [smsCode] against the MessageCentral [verificationId] via
  /// the verifyOtp Cloud Function, sign in with the returned custom token, and
  /// fetch/create the user profile.
  /// Returns the authenticated [UserModel].
  /// Throws Exception('USER_NOT_REGISTERED') if OTP is valid but the profile
  /// does not exist yet (caller should route to registration).
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

    try {
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/verifyOtp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': trimmedPhone,
          'verificationId': verificationId,
          'otp': smsCode.trim(),
        }),
      );

      // Guard: Cloud Functions may return an HTML error page (e.g. 404/500)
      // when the function is not deployed or crashes on startup.
      final body = response.body.trim();
      if (body.startsWith('<') || body.startsWith('<!')) {
        throw Exception('Server error. The OTP service is temporarily unavailable. Please try again later.');
      }

      final data = jsonDecode(body) as Map<String, dynamic>;

      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception(data['error']?.toString() ?? 'Failed to verify OTP.');
      }

      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        throw Exception('Authentication failed. Please try again.');
      }

      final userCredential = await _auth.signInWithCustomToken(customToken);
      final signedInUser = userCredential.user;
      if (signedInUser == null) {
        throw Exception('Authentication failed. Please try again.');
      }
      // Force a fresh ID token so the `phone_number` claim is present before we
      // touch Firestore, otherwise the first read can race the token refresh.
      await signedInUser.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Authentication failed (${e.code}).');
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }

    return await _fetchOrCreateUserSession(trimmedPhone);
  }

  /// Placeholder admin number used during development. It is not a real Indian
  /// mobile number, so it can only ever be "verified" via a Firebase *test*
  /// phone number — which every user of the app could enter. It must therefore
  /// never grant admin access in a shipped build.
  static const String _placeholderAdminPhone = '9999999999';

  Future<UserModel> _fetchOrCreateUserSession(String phone) async {
    // Admin check: if the phone is one of AppConstants.adminPhones, load or
    // create its admin profile in Firestore.
    //
    // Safety guard: refuse to bootstrap admin from the dev placeholder number in
    // a release build. It is not a real Indian mobile, so it can only ever be
    // "verified" through a Firebase test number — which any user could enter.
    final isPlaceholderInRelease =
        kReleaseMode && phone == _placeholderAdminPhone;
    if (isPlaceholderInRelease) {
      debugPrint(
        'Refusing admin bootstrap: $phone is the dev placeholder. '
        'Use a real admin number in release.',
      );
    } else if (AppConstants.adminPhones.contains(phone)) {
      final doc = await _usersRef.doc(phone).get();
      if (!doc.exists) {
        final adminUser = UserModel(
          id: phone,
          name: 'Shantinath Admin',
          phone: phone,
          village: 'Head Office',
          role: UserRole.admin,
          isApproved: true,
        );
        // Self-creating an admin doc needs the isBootstrapAdmin() branch of the
        // users create rule. Without it the profile never lands, and every
        // later isAdmin() check in the rules fails — so say that plainly
        // instead of surfacing a bare permission-denied.
        try {
          await _usersRef.doc(phone).set(adminUser.toJson());
        } catch (e) {
          throw Exception(
            'Could not create the admin profile. Deploy firestore.rules '
            '(firebase deploy --only firestore:rules) and sign in again. [$e]',
          );
        }
        return adminUser;
      }
      final data = doc.data() as Map<String, dynamic>;
      // A designated admin number must always be an approved admin. Upgrade an
      // existing customer/employee doc in place (e.g. a number previously used
      // for testing) so both the app and Firestore rules see role == 'admin'.
      //
      // The write needs the isBootstrapAdmin() self-update path in
      // firestore.rules. If those rules have not been deployed yet the update
      // is denied — don't let that block the login: fall back to an in-memory
      // admin session (the pre-existing behaviour) and log it, so the only
      // symptom is that the upgrade retries on the next sign-in.
      if (data['role'] != UserRole.admin.name || data['isApproved'] != true) {
        try {
          await _usersRef.doc(phone).update({
            'role': UserRole.admin.name,
            'isApproved': true,
          });
        } catch (e) {
          debugPrint(
            'Could not persist admin upgrade for $phone ($e). Deploy '
            'firestore.rules (isBootstrapAdmin) to make this stick.',
          );
        }
        data['role'] = UserRole.admin.name;
        data['isApproved'] = true;
      }
      return UserModel.fromJson(data);
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

    // Check for duplicate firm name to prevent sync conflicts.
    //
    // This is a collection-wide query, which Firestore security rules only
    // permit for admins (regular users can read just their own profile). For a
    // customer mid-registration the query is rejected with `permission-denied`,
    // so we treat any failure as "couldn't verify" and let registration
    // proceed rather than blocking a legitimate signup. True firm-level
    // uniqueness should be enforced server-side (Cloud Function / Admin SDK).
    try {
      final duplicateFirmQuery = await _usersRef
          .where('firmName', isEqualTo: trimmedFirmName)
          .limit(1)
          .get();
      if (duplicateFirmQuery.docs.isNotEmpty) {
        throw Exception(
            'The firm "$trimmedFirmName" is already registered under another account.');
      }
    } on FirebaseException catch (e) {
      // Permission denied (expected for non-admins) — skip the soft check.
      debugPrint('Skipping firm-name uniqueness check: ${e.code}');
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
      isApproved: false, // Customers must be approved by admin
    );

    // Save user to Firestore
    await _usersRef.doc(trimmedPhone).set(user.toJson());
    return user;
  }

  /// Update FCM Token for a user document in Firestore.
  Future<void> updateFcmToken(String phone, String token) async {
    try {
      await _usersRef.doc(phone.trim()).update({'fcmToken': token});
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  /// Update Approval status for a user.
  Future<void> updateApprovalStatus(String phone, bool isApproved) async {
    try {
      await _usersRef.doc(phone.trim()).update({'isApproved': isApproved});
    } catch (e) {
      throw Exception('Failed to update approval status: $e');
    }
  }

  /// Get a user by their phone number. Returns null if not found.
  Future<UserModel?> getUserByPhone(String phone) async {
    final doc = await _usersRef.doc(phone.trim()).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Fetch all users from Firestore.
  Future<List<UserModel>> getAllUsers() async {
    final snapshot = await _usersRef.get();
    return snapshot.docs
        .map((doc) => UserModel.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Get a user by their ID. Returns null if not found.
  Future<UserModel?> getUserById(String id) async {
    final queryId = (id == 'admin_001') ? AppConstants.adminPhones.first : id;
    final doc = await _usersRef.doc(queryId).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Fetch all synced Tally parties for registration lookup.
  Future<List<Map<String, dynamic>>> getTallyParties() async {
    try {
      final snapshot = await _db.collection('tally_parties').orderBy('name').get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error getting Tally parties: $e');
      return [];
    }
  }

  /// Fetch sensitive financials data for a user.
  Future<Map<String, dynamic>?> getFinancials(String phone) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(phone.trim())
          .collection('private')
          .doc('financials')
          .get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('Error getting financials for $phone: $e');
      return null;
    }
  }

  /// Update permissions and role for a user.
  Future<void> updatePermissions(String phone, List<String> permissions, {UserRole? role}) async {
    try {
      final updates = <String, dynamic>{
        'permissions': permissions,
      };
      if (role != null) {
        updates['role'] = role.name;
      }
      await _usersRef.doc(phone.trim()).update(updates);
    } catch (e) {
      throw Exception('Failed to update permissions: $e');
    }
  }

  /// Add a new employee or update an existing user's role to employee.
  Future<void> addEmployee(String phone, String name, List<String> initialPermissions) async {
    final trimmedPhone = phone.trim();
    final trimmedName = name.trim();
    if (trimmedPhone.length != 10 || !RegExp(r'^\d+$').hasMatch(trimmedPhone)) {
      throw Exception('A valid 10-digit phone number is required');
    }
    if (trimmedName.isEmpty) {
      throw Exception('Name is required');
    }

    try {
      final doc = await _usersRef.doc(trimmedPhone).get();
      if (doc.exists) {
        // Upgrade existing user to employee
        await _usersRef.doc(trimmedPhone).update({
          'role': UserRole.employee.name,
          'isApproved': true,
          'permissions': initialPermissions,
        });
      } else {
        // Create new employee doc
        final newEmployee = UserModel(
          id: trimmedPhone,
          name: trimmedName,
          phone: trimmedPhone,
          role: UserRole.employee,
          isApproved: true,
          permissions: initialPermissions,
        );
        await _usersRef.doc(trimmedPhone).set(newEmployee.toJson());
      }
    } catch (e) {
      throw Exception('Failed to add employee: $e');
    }
  }

  /// Demote an employee back to customer role and clear permissions.
  Future<void> removeEmployee(String phone) async {
    try {
      await _usersRef.doc(phone.trim()).update({
        'role': UserRole.customer.name,
        'permissions': <String>[],
      });
    } catch (e) {
      throw Exception('Failed to remove employee: $e');
    }
  }
}
