import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Service for managing file uploads with Firebase Storage.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Singleton pattern
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// Uploads a product image file to Firebase Storage.
  /// Stores it under `products/images/<productId>_<timestamp>.jpg`.
  /// Returns the download URL.
  Future<String> uploadProductImage(String productId, File file) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Extract file extension or default to .jpg
      final extension = file.path.split('.').last;
      final fileName = '${productId}_$timestamp.$extension';
      
      final ref = _storage.ref().child('products').child('images').child(fileName);
      
      // Upload the file
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/$extension'),
      );
      
      // Retrieve and return the download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload product image to Firebase Storage: $e');
    }
  }

  /// Uploads a banner image file to Firebase Storage.
  /// Stores it under `banners/images/<bannerId>_<timestamp>.jpg`.
  /// Returns the download URL.
  Future<String> uploadBannerImage(String bannerId, File file) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = file.path.split('.').last;
      final fileName = '${bannerId}_$timestamp.$extension';
      
      final ref = _storage.ref().child('banners').child('images').child(fileName);
      
      // Upload the file
      final uploadTask = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/$extension'),
      );
      
      // Retrieve and return the download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception('Failed to upload banner image to Firebase Storage: $e');
    }
  }
}
