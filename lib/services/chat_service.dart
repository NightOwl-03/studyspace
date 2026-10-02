import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/conversation_model.dart';
import '../models/message_model.dart';

/// All Supabase interactions for the real-time messaging feature.
///
/// FIX (real-time sync with web dashboard):
///   Uses explicit `postgres_changes` channel subscriptions so any INSERT
///   from ANY client (Flutter app OR owner web dashboard) triggers a re-fetch
///   and updates the UI instantly.
class ChatService {
  // ── Conversation streams ──────────────────────────────────────────────────

  /// Returns a [Stream] of all conversations for the currently signed-in user.
  /// Updates in real-time on INSERT or UPDATE to the conversations table.
  static Stream<List<Conversation>> getConversationsStream() {
    final userEmail = db.auth.currentUser?.email ?? '';
    if (userEmail.isEmpty) return const Stream.empty();

    final controller = StreamController<List<Conversation>>.broadcast();
    final channelName = 'conversations-${userEmail.hashCode}';

    Future<void> refetch() async {
      try {
        final rows = await db
            .from('conversations')
            .select()
            .eq('customer_email', userEmail)
            .order('last_message_time', ascending: false);

        final convos = (rows as List)
            .map((row) => Conversation.fromMap(row as Map<String, dynamic>))
            .toList();
        if (!controller.isClosed) {
          controller.add(await _enrichWithSpotNames(convos));
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // Emit immediately so the UI doesn't start blank.
    refetch();

    final channel = db
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_email',
            value: userEmail,
          ),
          callback: (_) => refetch(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_email',
            value: userEmail,
          ),
          callback: (_) => refetch(),
        )
        .subscribe();

    controller.onCancel = () {
      db.removeChannel(channel);
    };

    return controller.stream;
  }

  // ── Enrich conversations with spot name + owner profile picture ───────────

  /// Fetches study spot names and the owner's profile_picture_url for a batch
  /// of conversations.
  ///
  /// WHY TWO QUERIES instead of a single PostgREST join:
  ///   `study_spots.owner_id → owners.id` is a many-to-one FK. PostgREST
  ///   embeds the *referenced* table only when you hint the column name with
  ///   `owners!owner_id(...)`. Without the hint the response silently omits
  ///   the nested object — which is exactly why the avatar stayed as initials.
  ///
  ///   Using two explicit queries is simpler, guaranteed to work across all
  ///   Supabase PostgREST versions, and still only two round-trips total
  ///   regardless of how many conversations are in the list.
  ///
  ///   Query 1: study_spots  → gives us  spot name  +  owner_id
  ///   Query 2: owners       → gives us  profile_picture_url
  static Future<List<Conversation>> _enrichWithSpotNames(
    List<Conversation> convos,
  ) async {
    if (convos.isEmpty) return convos;

    final spotIds = convos.map((c) => c.studySpotId).toSet().toList();

    // ── Query 1: fetch spot name + owner_id ──────────────────────────────────
    final spotRows = await db
        .from('study_spots')
        .select('id, name, owner_id')
        .inFilter('id', spotIds);

    // spot_id → name
    final nameMap = <String, String>{};
    // spot_id → owner_id  (so we can look up the picture in query 2)
    final ownerIdBySpot = <String, String>{};

    for (final r in spotRows) {
      final spotId = r['id'] as String;
      nameMap[spotId] = r['name'] as String? ?? '';
      final ownerId = r['owner_id'];
      if (ownerId is String && ownerId.isNotEmpty) {
        ownerIdBySpot[spotId] = ownerId;
      }
    }

    // ── Query 2: fetch profile_picture_url from owners ───────────────────────
    final ownerIds = ownerIdBySpot.values.toSet().toList();
    final picByOwner = <String, String?>{};

    if (ownerIds.isNotEmpty) {
      final ownerRows = await db
          .from('owners')
          .select('id, profile_picture_url')
          .inFilter('id', ownerIds);

      for (final r in ownerRows) {
        final ownerId = r['id'] as String;
        final url = r['profile_picture_url'] as String?;
        // Only store non-empty URLs — treat empty strings the same as null
        picByOwner[ownerId] = (url != null && url.isNotEmpty) ? url : null;
      }
    }

    // ── Merge into new Conversation copies ───────────────────────────────────
    return convos.map((c) {
      final ownerId = ownerIdBySpot[c.studySpotId];
      final picUrl = ownerId != null ? picByOwner[ownerId] : null;

      return Conversation(
        id: c.id,
        studySpotId: c.studySpotId,
        reservationId: c.reservationId,
        customerEmail: c.customerEmail,
        customerName: c.customerName,
        lastMessage: c.lastMessage,
        lastMessageTime: c.lastMessageTime,
        unread: c.unread,
        createdAt: c.createdAt,
        studySpotName: nameMap[c.studySpotId],
        profilePictureUrl: picUrl,
      );
    }).toList();
  }

  // ── Message stream ────────────────────────────────────────────────────────

  /// Returns a [Stream] of all messages inside a conversation, ordered oldest
  /// first. Emits a fresh list on every INSERT to `messages` — whether sent
  /// by the Flutter user OR the owner from the web dashboard.
  ///
  /// Why NOT `.stream()`:
  ///   `.stream()` relies on Supabase Realtime broadcast, which only reflects
  ///   changes made through the same Realtime connection. Cross-client inserts
  ///   (e.g. from the owner's web dashboard via the REST API) are NOT broadcast
  ///   unless `postgres_changes` is explicitly subscribed. This implementation
  ///   uses `postgres_changes` so owner replies always appear instantly.
  static Stream<List<Message>> getMessagesStream(String conversationId) {
    final controller = StreamController<List<Message>>.broadcast();

    Future<void> refetch() async {
      try {
        final rows = await db
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: true);

        if (!controller.isClosed) {
          controller.add(rows.map(Message.fromMap).toList());
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // Kick off an immediate fetch so the UI doesn't start blank.
    refetch();

    final channel = db
        .channel('messages-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) => refetch(),
        )
        .subscribe();

    controller.onCancel = () {
      db.removeChannel(channel);
    };

    return controller.stream;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  static Future<void> sendMessage({
    required String conversationId,
    required String messageText,
  }) async {
    final text = messageText.trim();
    if (text.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();

    await db.from('messages').insert({
      'conversation_id': conversationId,
      'sender_type': 'user',
      'message': text,
      'created_at': now,
    });

    await db
        .from('conversations')
        .update({
          'last_message': text,
          'last_message_time': now,
          'unread': false,
        })
        .eq('id', conversationId);
  }

  static Future<Conversation> createNewConversation({
    required String studySpotId,
    required String firstMessage,
    String? reservationId,
  }) async {
    final user = db.auth.currentUser;
    if (user == null) throw Exception('Not signed in.');

    final text = firstMessage.trim();
    if (text.isEmpty) throw Exception('Message cannot be empty.');

    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await db
        .from('conversations')
        .select('id')
        .eq('customer_email', user.email ?? '')
        .eq('study_spot_id', studySpotId)
        .maybeSingle();

    late String conversationId;

    if (existing != null) {
      conversationId = existing['id'] as String;
    } else {
      final convoRow = await db
          .from('conversations')
          .insert({
            'study_spot_id': studySpotId,
            if (reservationId != null) 'reservation_id': reservationId,
            'customer_email': user.email,
            'customer_name':
                user.userMetadata?['full_name'] as String? ?? user.email,
            'last_message': text,
            'last_message_time': now,
            'unread': true,
            'created_at': now,
          })
          .select()
          .single();

      conversationId = convoRow['id'] as String;
    }

    await sendMessage(conversationId: conversationId, messageText: text);

    final row = await db
        .from('conversations')
        .select()
        .eq('id', conversationId)
        .single();

    return Conversation.fromMap(row);
  }

  static Future<void> markAsRead(String conversationId) async {
    await db
        .from('conversations')
        .update({'unread': false})
        .eq('id', conversationId);
  }

  static Future<int> getUnreadCount() async {
    final email = db.auth.currentUser?.email ?? '';
    final rows = await db
        .from('conversations')
        .select('id')
        .eq('customer_email', email)
        .eq('unread', true);
    return (rows as List).length;
  }

  // ── Real-time unread message badge stream ─────────────────────────────────

  /// Emits the live count of conversations where `unread == true`.
  ///
  /// Mirrors the pattern used by [NotificationService.unreadCountStream].
  /// Subscribe once in [HomeScreen.initState] and the Messages badge updates
  /// automatically whenever the owner replies from the web dashboard — no
  /// polling, no manual zeroing.
  ///
  /// The badge resets to 0 the moment [markAsRead] is called for a
  /// conversation (the UPDATE triggers a re-fetch through this stream).
  static Stream<int> unreadMessagesStream() {
    final email = db.auth.currentUser?.email ?? '';
    if (email.isEmpty) return const Stream.empty();

    final controller = StreamController<int>.broadcast();

    Future<void> refetch() async {
      try {
        final count = await getUnreadCount();
        if (!controller.isClosed) controller.add(count);
      } catch (_) {
        if (!controller.isClosed) controller.add(0);
      }
    }

    // Emit immediately so the badge is correct on first build.
    refetch();

    final channel = db
        .channel('unread-messages-${email.hashCode}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_email',
            value: email,
          ),
          callback: (_) => refetch(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_email',
            value: email,
          ),
          callback: (_) => refetch(),
        )
        .subscribe();

    controller.onCancel = () => db.removeChannel(channel);
    return controller.stream;
  }
}
