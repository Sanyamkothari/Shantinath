import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityLog {
  final String id;
  final String actorId;
  final String actorName;
  final String actorRole;
  final String action;
  final String? targetType;
  final String? targetId;
  final String summary;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ActivityLog({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    this.targetType,
    this.targetId,
    required this.summary,
    this.metadata = const {},
    required this.createdAt,
  });

  factory ActivityLog.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    if (json['createdAt'] is Timestamp) {
      parsedDate = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is String) {
      parsedDate = DateTime.parse(json['createdAt'] as String);
    } else {
      parsedDate = DateTime.now();
    }

    return ActivityLog(
      id: json['id'] as String? ?? '',
      actorId: json['actorId'] as String? ?? '',
      actorName: json['actorName'] as String? ?? '',
      actorRole: json['actorRole'] as String? ?? '',
      action: json['action'] as String? ?? '',
      targetType: json['targetType'] as String?,
      targetId: json['targetId'] as String?,
      summary: json['summary'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'actorId': actorId,
      'actorName': actorName,
      'actorRole': actorRole,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'summary': summary,
      'metadata': metadata,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
