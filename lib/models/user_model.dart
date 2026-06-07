/// User roles within the application.
enum UserRole {
  customer,
  admin;

  /// Converts a string value to the corresponding [UserRole].
  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => UserRole.customer,
    );
  }
}

/// Represents an authenticated user (customer or admin).
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String village;
  final UserRole role;
  final String firmName;
  final String seedLicenceNumber;
  final String fertilizerLicenceNumber;
  final String proprietorName;
  final String gstNo;
  final String secondLicenceNumber;
  final String taluka;
  final String district;
  final String khatIdNo;
  final String customerType; // "wholesale" or "retail"

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.village = '',
    this.role = UserRole.customer,
    this.firmName = '',
    this.seedLicenceNumber = '',
    this.fertilizerLicenceNumber = '',
    this.proprietorName = '',
    this.gstNo = '',
    this.secondLicenceNumber = '',
    this.taluka = '',
    this.district = '',
    this.khatIdNo = '',
    this.customerType = '',
  });

  /// Whether this user has admin privileges.
  bool get isAdmin => role == UserRole.admin;

  /// Whether this user is a regular customer.
  bool get isCustomer => role == UserRole.customer;

  /// Display-friendly role text in English.
  String get roleText => isAdmin ? 'Admin' : 'Customer';

  /// Display-friendly role text in Hindi.
  String get roleTextHi => isAdmin ? 'एडमिन' : 'ग्राहक';

  /// Creates a [UserModel] from a JSON map.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      village: json['village'] as String? ?? '',
      role: UserRole.fromString(json['role'] as String? ?? 'customer'),
      firmName: json['firmName'] as String? ?? '',
      seedLicenceNumber: json['seedLicenceNumber'] as String? ?? '',
      fertilizerLicenceNumber: json['fertilizerLicenceNumber'] as String? ?? '',
      proprietorName: json['proprietorName'] as String? ?? '',
      gstNo: json['gstNo'] as String? ?? '',
      secondLicenceNumber: json['secondLicenceNumber'] as String? ?? '',
      taluka: json['taluka'] as String? ?? '',
      district: json['district'] as String? ?? '',
      khatIdNo: json['khatIdNo'] as String? ?? '',
      customerType: json['customerType'] as String? ?? '',
    );
  }

  /// Serializes this [UserModel] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'village': village,
      'role': role.name,
      'firmName': firmName,
      'seedLicenceNumber': seedLicenceNumber,
      'fertilizerLicenceNumber': fertilizerLicenceNumber,
      'proprietorName': proprietorName,
      'gstNo': gstNo,
      'secondLicenceNumber': secondLicenceNumber,
      'taluka': taluka,
      'district': district,
      'khatIdNo': khatIdNo,
      'customerType': customerType,
    };
  }

  /// Returns a copy of this [UserModel] with the given fields replaced.
  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? village,
    UserRole? role,
    String? firmName,
    String? seedLicenceNumber,
    String? fertilizerLicenceNumber,
    String? proprietorName,
    String? gstNo,
    String? secondLicenceNumber,
    String? taluka,
    String? district,
    String? khatIdNo,
    String? customerType,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      village: village ?? this.village,
      role: role ?? this.role,
      firmName: firmName ?? this.firmName,
      seedLicenceNumber: seedLicenceNumber ?? this.seedLicenceNumber,
      fertilizerLicenceNumber: fertilizerLicenceNumber ?? this.fertilizerLicenceNumber,
      proprietorName: proprietorName ?? this.proprietorName,
      gstNo: gstNo ?? this.gstNo,
      secondLicenceNumber: secondLicenceNumber ?? this.secondLicenceNumber,
      taluka: taluka ?? this.taluka,
      district: district ?? this.district,
      khatIdNo: khatIdNo ?? this.khatIdNo,
      customerType: customerType ?? this.customerType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UserModel && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'UserModel(id: $id, name: $name, phone: $phone, firmName: $firmName, customerType: $customerType)';
}
