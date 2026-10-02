import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/notification_service.dart';

/// Displays in-app notifications with live real-time updates via StreamBuilder.
///
/// Changes vs original:
///  • All / Unread tab bar — filter without extra DB calls.
///  • Notifications that arrived as a pop-up (snackbar) while the user was in
///    the app are marked with a small "Received as pop-up" chip so nothing
///    feels lost.  (The chip appears for every unread notification because
///    AppNotificationBanner fires for every INSERT.)
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late final Stream<List<UserNotification>> _stream;
  late final TabController _tabController;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _stream = NotificationService.notificationsStream();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    await NotificationService.markAllAsRead();
    setState(() => _markingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_markingAll)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF3B82F6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
        // ── Tab bar ──────────────────────────────────────────────────────────
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.grey[500],
          indicatorColor: const Color(0xFF3B82F6),
          indicatorWeight: 2.5,
          labelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 13),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unread'),
          ],
        ),
      ),

      body: StreamBuilder<List<UserNotification>>(
        stream: _stream,
        builder: (context, snapshot) {
          // ── Loading ────────────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // ── Error ──────────────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load notifications.',
                    style: GoogleFonts.inter(color: Colors.redAccent),
                  ),
                ],
              ),
            );
          }

          final all = snapshot.data ?? [];
          final unread = all.where((n) => !n.isRead).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _NotificationList(
                notifications: all,
                onMarkRead: (id) => NotificationService.markAsRead(id),
              ),
              _NotificationList(
                notifications: unread,
                onMarkRead: (id) => NotificationService.markAsRead(id),
                emptyMessage: "You're all caught up!",
                emptySubtitle: 'No unread notifications.',
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── List widget (shared between tabs) ────────────────────────────────────────

class _NotificationList extends StatelessWidget {
  final List<UserNotification> notifications;
  final Future<void> Function(String id) onMarkRead;
  final String emptyMessage;
  final String emptySubtitle;

  const _NotificationList({
    required this.notifications,
    required this.onMarkRead,
    this.emptyMessage = 'No notifications yet',
    this.emptySubtitle = "You're all caught up!",
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                size: 48,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              emptySubtitle,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.black38),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final n = notifications[index];
        return _NotificationTile(
          notification: n,
          onTap: () async {
            if (!n.isRead) await onMarkRead(n.id);
          },
        );
      },
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final UserNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  ({IconData icon, Color color}) get _visual {
    switch (notification.type) {
      case 'new_message':
        return (
          icon: Icons.chat_bubble_rounded,
          color: const Color(0xFF3B82F6),
        );
      case 'reservation_confirmed':
        return (icon: Icons.check_circle_rounded, color: Colors.green);
      case 'reservation_cancelled':
        return (icon: Icons.cancel_rounded, color: Colors.redAccent);
      case 'reservation_pending':
        return (icon: Icons.hourglass_top_rounded, color: Colors.orange);
      case 'points_earned':
        return (icon: Icons.stars_rounded, color: Colors.amber);
      case 'new_partner':
        return (
          icon: Icons.local_offer_rounded,
          color: const Color(0xFF3B82F6),
        );
      case 'closing_soon':
        return (icon: Icons.warning_rounded, color: Colors.orange);
      default:
        return (icon: Icons.notifications_rounded, color: Colors.blueGrey);
    }
  }

  String get _relativeTime {
    final diff = DateTime.now().difference(notification.createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  /// A notification that arrived "just now" (< 5 min) and is still unread
  /// almost certainly showed as a pop-up banner/snackbar — surface that.
  bool get _arrivedAsPopUp {
    final diff = DateTime.now().difference(notification.createdAt);
    return !notification.isRead && diff.inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notification.isRead
              ? Colors.white
              : const Color(0xFF3B82F6).withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.isRead
                ? Colors.grey.shade200
                : const Color(0xFF3B82F6).withOpacity(0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon bubble ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: v.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(v.icon, color: v.color, size: 22),
            ),
            const SizedBox(width: 14),

            // ── Text content ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: GoogleFonts.poppins(
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.4,
                    ),
                  ),

                  // ── "Also shown as pop-up" chip ──────────────────────────
                  // Visible for notifications that fired a snackbar banner
                  // so users know they were already alerted in-app.
                  if (_arrivedAsPopUp) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          size: 12,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Also shown as a pop-up',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey[400],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Unread dot ───────────────────────────────────────────────
            if (!notification.isRead)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── App-level banner ──────────────────────────────────────────────────────────

/// Wrap around your bottom-nav shell to show snackbars for new notifications.
///
/// ```dart
/// return AppNotificationBanner(child: Scaffold(...));
/// ```
class AppNotificationBanner extends StatefulWidget {
  final Widget child;
  const AppNotificationBanner({super.key, required this.child});

  @override
  State<AppNotificationBanner> createState() => _AppNotificationBannerState();
}

class _AppNotificationBannerState extends State<AppNotificationBanner> {
  StreamSubscription<UserNotification>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = NotificationService.newNotificationStream().listen(_onNew);
  }

  void _onNew(UserNotification n) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.white,
        elevation: 6,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFF3B82F6),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    n.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
