import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dependency to add in pubspec.yaml:
//
//   flutter_local_notifications: ^17.2.3
//
// Android: add to android/app/src/main/AndroidManifest.xml, inside <manifest>:
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//   <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
//   <uses-permission android:name="android.permission.VIBRATE"/>
//
// iOS: enable Push Notifications capability in Xcode → Signing & Capabilities.
// ─────────────────────────────────────────────────────────────────────────────

/// A single notification item from public.user_notifications.
class UserNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const UserNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.expiresAt,
  });

  factory UserNotification.fromMap(Map<String, dynamic> map) {
    return UserNotification(
      id: map['id'] as String,
      type: (map['notification_type'] ?? map['type'] ?? 'general') as String,
      title: map['title'] as String,
      message: (map['message'] ?? map['body'] ?? '') as String,
      isRead: map['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: map['expires_at'] != null
          ? DateTime.parse(map['expires_at'] as String)
          : null,
    );
  }

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

// ─────────────────────────────────────────────────────────────────────────────
// Local push notification helper
// ─────────────────────────────────────────────────────────────────────────────

/// Call [LocalPushService.init] once from main() (before runApp).
class LocalPushService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static int _nextId = 0;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Request runtime permission on Android 13+.
    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();
    }
  }

  static Future<void> show(UserNotification n) async {
    const androidDetails = AndroidNotificationDetails(
      'user_notifications', // channel id
      'App Notifications', // channel name
      channelDescription: 'In-app alerts for messages and reservations',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.show(
      _nextId++,
      n.title,
      n.message,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService
// ─────────────────────────────────────────────────────────────────────────────

/// Handles fetching and managing in-app notifications with real-time support.
///
/// Real-time flow:
///   1. [notificationsStream] powers the NotificationsScreen list via StreamBuilder.
///   2. [newNotificationStream] powers the app-level banner (AppNotificationBanner).
///   3. [newNotificationStream] also fires a local push notification so the user
///      sees an alert even when the app is backgrounded.
///
/// Setup: call [NotificationService.initLocalNotifications] once in main()
/// before runApp so local push is ready.
class NotificationService {
  // ── Init ──────────────────────────────────────────────────────────────────

  /// Call this once from main() before runApp.
  static Future<void> initLocalNotifications() => LocalPushService.init();

  // ── Fetch ─────────────────────────────────────────────────────────────────

  /// Returns all non-expired notifications for the signed-in user, newest first.
  static Future<List<UserNotification>> fetchNotifications() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final now = DateTime.now().toIso8601String();

    final data = await db
        .from('user_notifications')
        .select()
        .eq('user_id', userId)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => UserNotification.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // ── Real-time full list ───────────────────────────────────────────────────

  /// Emits the full, up-to-date notification list in real-time.
  ///
  /// Wire into a StreamBuilder on NotificationsScreen — every INSERT/UPDATE
  /// from a DB trigger automatically re-fetches and pushes the new list.
  static Stream<List<UserNotification>> notificationsStream() {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return const Stream.empty();

    final controller = StreamController<List<UserNotification>>.broadcast();

    Future<void> refetch() async {
      try {
        final notifications = await fetchNotifications();
        if (!controller.isClosed) controller.add(notifications);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // Emit immediately on subscribe.
    refetch();

    final channel = db
        .channel('user-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => refetch(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => refetch(),
        )
        .subscribe();

    controller.onCancel = () => db.removeChannel(channel);
    return controller.stream;
  }

  // ── Real-time new-only stream ─────────────────────────────────────────────

  /// Emits each brand-new notification as it is inserted.
  ///
  /// Used by [AppNotificationBanner] for the snackbar AND for local push.
  /// Local push fires here so the user sees the alert even when backgrounded.
  static Stream<UserNotification> newNotificationStream() {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return const Stream.empty();

    final controller = StreamController<UserNotification>.broadcast();

    final channel = db
        .channel('new-notification-alert-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            try {
              final newRow = payload.newRecord;
              if (newRow.isNotEmpty && !controller.isClosed) {
                final n = UserNotification.fromMap(newRow);
                controller.add(n);
                // ↓ Fire local push — visible even when app is backgrounded.
                LocalPushService.show(n);
              }
            } catch (_) {
              // Silently ignore parse errors.
            }
          },
        )
        .subscribe();

    controller.onCancel = () => db.removeChannel(channel);
    return controller.stream;
  }

  // ── Mark as read ──────────────────────────────────────────────────────────

  static Future<void> markAsRead(String notificationId) async {
    await db
        .from('user_notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<void> markAllAsRead() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return;

    await db
        .from('user_notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  // ── Unread count ──────────────────────────────────────────────────────────

  /// Emits the live unread count. Use this to drive a badge on the nav icon.
  static Stream<int> unreadCountStream() {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return notificationsStream().map(
      (list) => list.where((n) => !n.isRead && !n.isExpired).length,
    );
  }
}
