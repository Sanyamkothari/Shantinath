/// Represents a broadcast message / announcement sent by the admin to all customers.
class BroadcastMessage {
  final String id;
  final String title;
  final String titleMr; // Marathi translation
  final String body;
  final String bodyMr; // Marathi translation
  final String imageUrl;
  final DateTime createdAt;
  final String senderId;

  const BroadcastMessage({
    required this.id,
    required this.title,
    required this.titleMr,
    required this.body,
    required this.bodyMr,
    this.imageUrl = '',
    required this.createdAt,
    this.senderId = '',
  });

  /// Creates a [BroadcastMessage] from a JSON map.
  factory BroadcastMessage.fromJson(Map<String, dynamic> json) {
    return BroadcastMessage(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleMr: (json['titleMr'] ?? json['titleHi'] ?? '') as String,
      body: json['body'] as String? ?? '',
      bodyMr: (json['bodyMr'] ?? json['bodyHi'] ?? '') as String,
      imageUrl: json['imageUrl'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      senderId: json['senderId'] as String? ?? '',
    );
  }

  /// Serializes this [BroadcastMessage] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'titleMr': titleMr,
      'body': body,
      'bodyMr': bodyMr,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
      'senderId': senderId,
    };
  }

  /// Returns a copy of this [BroadcastMessage] with fields replaced.
  BroadcastMessage copyWith({
    String? id,
    String? title,
    String? titleMr,
    String? body,
    String? bodyMr,
    String? imageUrl,
    DateTime? createdAt,
    String? senderId,
  }) {
    return BroadcastMessage(
      id: id ?? this.id,
      title: title ?? this.title,
      titleMr: titleMr ?? this.titleMr,
      body: body ?? this.body,
      bodyMr: bodyMr ?? this.bodyMr,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      senderId: senderId ?? this.senderId,
    );
  }

  /// Sample mock notifications/broadcasts for initial load or preview.
  static List<BroadcastMessage> getSampleBroadcasts() {
    final now = DateTime.now();
    return [
      BroadcastMessage(
        id: 'B001',
        title: 'New Cotton Seeds Stock Arrived!',
        titleMr: 'नवीन कापूस बियाणे स्टॉक उपलब्ध!',
        body: 'Premium Rocky BG-II cotton seeds are now back in stock. Order early to avoid shortage.',
        bodyMr: 'प्रीमियम रॉकी बीजी-II कापूस बियाणे आता पुन्हा स्टॉकमध्ये आले आहेत. टंचाई टाळण्यासाठी लवकर ऑर्डर करा.',
        imageUrl: 'https://images.unsplash.com/photo-1594900222129-a1b9201f9e98?auto=format&fit=crop&q=80&w=400',
        createdAt: now.subtract(const Duration(hours: 2)),
        senderId: 'admin',
      ),
      BroadcastMessage(
        id: 'B002',
        title: 'Monsoon Fertilizer Offer',
        titleMr: 'मान्सून खत विशेष ऑफर',
        body: 'Get 5% discount on bulk orders of Mahadhan SSP fertilizer this week.',
        bodyMr: 'या आठवड्यात महाधन एसएसपी खताच्या मोठ्या ऑर्डरवर ५% सूट मिळवा.',
        imageUrl: 'https://images.unsplash.com/photo-1585320806297-9794b3e4eeae?auto=format&fit=crop&q=80&w=400',
        createdAt: now.subtract(const Duration(days: 1)),
        senderId: 'admin',
      ),
    ];
  }
}
