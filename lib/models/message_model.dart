/// Which side of the conversation sent the message.
/// Matches the `sender_type` CHECK constraint in the `messages` table:
///   CHECK (sender_type IN ('owner', 'user'))
enum SenderType { user, owner }

/// Represents a single chat message.
/// Maps directly to the `messages` table in Supabase.
class Message {
  final String id;
  final String conversationId;
  final SenderType senderType;
  final String message;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.message,
    required this.createdAt,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    final raw = map['sender_type'] as String? ?? 'user';
    return Message(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderType: raw == 'owner' ? SenderType.owner : SenderType.user,
      message: map['message'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  bool get isFromUser => senderType == SenderType.user;
  bool get isFromOwner => senderType == SenderType.owner;

  /// HH:MM display string for the message timestamp
  String get timeLabel {
    final h = createdAt.hour.toString().padLeft(2, '0');
    final m = createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
