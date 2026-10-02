/// Represents a chat thread between a user and a study spot (owner).
/// Maps directly to the `conversations` table in Supabase.
class Conversation {
  final String id;
  final String studySpotId;
  final String? reservationId;
  final String customerEmail;
  final String? customerName;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final bool unread;
  final DateTime createdAt;

  // Populated via JOIN when fetching conversation list
  final String? studySpotName;

  // FIX: Owner's profile picture from the owners table.
  // Populated by ChatService._enrichWithSpotNames via the
  // study_spots → owners join.
  final String? profilePictureUrl;

  const Conversation({
    required this.id,
    required this.studySpotId,
    this.reservationId,
    required this.customerEmail,
    this.customerName,
    this.lastMessage,
    this.lastMessageTime,
    required this.unread,
    required this.createdAt,
    this.studySpotName,
    this.profilePictureUrl, // NEW
  });

  factory Conversation.fromMap(Map<String, dynamic> map) {
    // study_spots name comes in via a nested join:
    //   { "study_spots": { "name": "...", "owners": { "profile_picture_url": "..." } } }
    final spotJoin = map['study_spots'];
    final spotName = spotJoin is Map ? spotJoin['name'] as String? : null;

    // profile_picture_url may be injected directly by _enrichWithSpotNames
    // OR arrive nested under study_spots.owners (if the select join includes it).
    String? picUrl;
    if (map['profile_picture_url'] != null) {
      picUrl = map['profile_picture_url'] as String?;
    } else if (spotJoin is Map) {
      final ownerJoin = spotJoin['owners'];
      if (ownerJoin is Map) {
        picUrl = ownerJoin['profile_picture_url'] as String?;
      }
    }

    return Conversation(
      id: map['id'] as String,
      studySpotId: map['study_spot_id'] as String,
      reservationId: map['reservation_id'] as String?,
      customerEmail: map['customer_email'] as String,
      customerName: map['customer_name'] as String?,
      lastMessage: map['last_message'] as String?,
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'] as String).toLocal()
          : null,
      unread: map['unread'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      studySpotName: spotName,
      profilePictureUrl: picUrl,
    );
  }

  /// Display name shown in the chat list header
  String get displayName => studySpotName ?? 'Study Spot';

  /// Initials for the avatar fallback
  String get initials {
    final name = studySpotName ?? customerName ?? '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// Friendly relative timestamp for the chat list
  String get relativeTime {
    if (lastMessageTime == null) return '';
    final now = DateTime.now();
    final diff = now.difference(lastMessageTime!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }
}
