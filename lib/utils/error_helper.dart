import 'package:firebase_auth/firebase_auth.dart';

/// Converts low-level exceptions (Firebase, network, raw `Exception`s) into a
/// short, user-friendly message. Keeps technical noise like
/// `[cloud_firestore/permission-denied]` out of the UI.
///
/// Pass [isMarathi] to get the Marathi variant for generic failures.
String friendlyError(Object error, {bool isMarathi = false}) {
  // Firestore / Firebase-core errors expose a machine-readable `code`.
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return isMarathi
            ? 'ही कृती करण्याची परवानगी नाही.'
            : 'You do not have permission to do this.';
      case 'unavailable':
      case 'network-request-failed':
        return isMarathi
            ? 'इंटरनेट कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.'
            : 'Network problem. Check your connection and try again.';
      case 'not-found':
        return isMarathi ? 'माहिती सापडली नाही.' : 'The requested data was not found.';
      case 'deadline-exceeded':
        return isMarathi
            ? 'विनंती वेळेत पूर्ण झाली नाही. पुन्हा प्रयत्न करा.'
            : 'The request timed out. Please try again.';
    }
    // Fall back to Firebase's own message if it provided one.
    if (error.message != null && error.message!.isNotEmpty) {
      return error.message!;
    }
  }

  // Firebase Auth specific failures.
  if (error is FirebaseAuthException) {
    return error.message ??
        (isMarathi ? 'प्रमाणीकरण अयशस्वी झाले.' : 'Authentication failed.');
  }

  // Our own `throw Exception('Some readable message')` — strip the prefix.
  final raw = error.toString();
  const prefix = 'Exception: ';
  if (raw.startsWith(prefix)) {
    return raw.substring(prefix.length);
  }

  return isMarathi
      ? 'काहीतरी चूक झाली. कृपया पुन्हा प्रयत्न करा.'
      : 'Something went wrong. Please try again.';
}
