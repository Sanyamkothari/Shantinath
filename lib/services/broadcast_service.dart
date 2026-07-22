import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shantinath_agro/models/broadcast_message.dart';

/// Service class to manage Firestore transactions for broadcast messages.
class BroadcastService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference get _broadcastsRef => _db.collection('broadcasts');

  static final BroadcastService _instance = BroadcastService._internal();
  factory BroadcastService() => _instance;
  BroadcastService._internal();

  /// Retrieve all broadcasts. Seeds the database with default announcements if empty.
  Future<List<BroadcastMessage>> getAllBroadcasts() async {
    final snapshot = await _broadcastsRef.get();

    if (snapshot.docs.isEmpty) {
      final samples = BroadcastMessage.getSampleBroadcasts();
      final batch = _db.batch();

      for (final msg in samples) {
        final docRef = _broadcastsRef.doc(msg.id);
        batch.set(docRef, msg.toJson());
      }

      await batch.commit();

      final currentSnapshot = await _broadcastsRef.orderBy('createdAt', descending: true).get();
      return currentSnapshot.docs
          .map((doc) => BroadcastMessage.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    }

    final list = snapshot.docs
        .map((doc) => BroadcastMessage.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
    
    // Sort by createdAt descending
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Publish a new broadcast message to Firestore.
  Future<BroadcastMessage> addBroadcast(BroadcastMessage message) async {
    final docRef = _broadcastsRef.doc(message.id.isEmpty ? null : message.id);
    final newMessage = message.copyWith(
      id: docRef.id,
      createdAt: DateTime.now(),
    );
    await docRef.set(newMessage.toJson());
    return newMessage;
  }

  /// Delete a past broadcast message from Firestore.
  Future<bool> deleteBroadcast(String id) async {
    await _broadcastsRef.doc(id).delete();
    return true;
  }
}
