import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: unused_import
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../services/auth_service.dart';
import '../services/reservation_service.dart';
import '../models/conversation_model.dart';
import '../services/chat_service.dart';
import 'chat_room_screen.dart';
import '../widgets/rating_dialog.dart';

class ReservationsHistoryScreen extends StatefulWidget {
  const ReservationsHistoryScreen({super.key});

  @override
  State<ReservationsHistoryScreen> createState() =>
      _ReservationsHistoryScreenState();
}

class _ReservationsHistoryScreenState extends State<ReservationsHistoryScreen> {
  final String? _userId = AuthService.currentUser?.id;

  // ── Time format helper ────────────────────────────────────────────────────
  String _fmtTime(dynamic raw) {
    if (raw == null) return '—';
    final parts = raw.toString().split(':');
    if (parts.length >= 2) return '${parts[0]}:${parts[1]}';
    return raw.toString();
  }

  // ── FIX 1: De-duplicate by booking_reference ─────────────────────────────
  // The stream can return multiple rows from the view when a reservation has
  // more than one seat detail row joined in.  We keep only the first row we
  // see for each booking reference so every card appears exactly once.
  List<Map<String, dynamic>> _deduplicate(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      // Build the same display key we use in _buildReservationCard
      final String resId = row['id'] as String;
      final String? dbRef = row['booking_reference'] as String?;
      final String key = dbRef != null && dbRef.isNotEmpty
          ? dbRef
          : resId.replaceAll('-', '').toUpperCase().substring(0, 8);

      if (seen.add(key)) {
        result.add(row); // add() returns false if already present
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'My Reservations',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: _userId == null
          ? const Center(child: Text('Please log in to view reservations.'))
          // ── IMPORTANT: reservation_summary_view must include the
          // booking_reference column from the reservations table.
          // If booking refs still show wrong, run this in Supabase SQL editor:
          //
          //   CREATE OR REPLACE VIEW reservation_summary_view AS
          //   SELECT
          //     r.*,
          //     t.table_number
          //   FROM reservations r
          //   LEFT JOIN study_spot_tables t ON t.id = (
          //     SELECT rd.table_id FROM reservation_details rd
          //     WHERE rd.reservation_id = r.id LIMIT 1
          //   );
          //
          // This ensures booking_reference, table_number, and all other
          // reservation columns are available to the Flutter app.
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: db
                  .from('reservation_summary_view')
                  .stream(primaryKey: ['id'])
                  .eq('user_id', _userId)
                  .order('reservation_date', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState();
                }

                // ── Apply de-duplication before building the list ──────────
                final unique = _deduplicate(snapshot.data!);

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: unique.length,
                  itemBuilder: (context, index) =>
                      _buildReservationCard(context, unique[index]),
                );
              },
            ),
    );
  }

  // ── Reservation Card ──────────────────────────────────────────────────────
  Widget _buildReservationCard(BuildContext context, Map<String, dynamic> res) {
    final String status = res['reservation_status'] ?? 'pending';
    final DateTime date = DateTime.parse(res['reservation_date'].toString());
    final String resId = res['id'] as String;
    final String spotId = res['study_spot_id'] as String;

    final String? dbRef = res['booking_reference'] as String?;
    final String bookingRef = dbRef != null && dbRef.isNotEmpty
        ? '#$dbRef'
        : '#${resId.replaceAll('-', '').toUpperCase().substring(0, 8)}';

    final int numSeats = ((res['number_of_seats'] ?? 1) as num).toInt();
    final String seatsLabel = '$numSeats ${numSeats == 1 ? 'Seat' : 'Seats'}';
    final String tableNum = res['table_number']?.toString() ?? 'T1';
    final String assignmentLabel = '$seatsLabel at Table $tableNum';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Coloured top accent strip ──────────────────────────────────
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: _statusColor(status),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: booking ref + status badge ──────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.confirmation_number_rounded,
                          size: 15,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          bookingRef,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    _buildStatusBadge(status),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                // ── Detail rows ──────────────────────────────────────────
                _InfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value:
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.login_rounded,
                  label: 'Check-in',
                  value: _fmtTime(res['start_time']),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.logout_rounded,
                  label: 'Check-out',
                  value: _fmtTime(res['end_time']),
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.assignment_rounded,
                  label: 'Assignment',
                  value: assignmentLabel,
                ),

                const SizedBox(height: 14),

                // ── Action buttons ───────────────────────────────────────
                if (status == 'completed')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showReviewDialog(context, resId, spotId),
                      icon: const Icon(Icons.star_rounded, size: 18),
                      label: Text(
                        'Rate & Review',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                // ── FIX 2 & 3: Cancel + Message buttons side by side ─────
                if (status == 'pending' || status == 'confirmed')
                  Row(
                    children: [
                      // Cancel Booking button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showCancelDialog(context, resId),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Message button — navigates to ChatRoomScreen
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openChat(context, spotId, resId),
                          icon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'Message',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Open chat ─────────────────────────────────────────────────────────────
  // Looks for an existing conversation for this studySpotId.
  // • Found  → enrich with spot name → ChatRoomScreen.
  // • Not found → show a "first message" dialog, then create + navigate.
  Future<void> _openChat(
    BuildContext context,
    String spotId,
    String reservationId,
  ) async {
    try {
      // 1. Fetch spot name + owner_id in one query.
      final spotRow = await db
          .from('study_spots')
          .select('name, owner_id')
          .eq('id', spotId)
          .maybeSingle();
      final spotName = spotRow != null ? spotRow['name'] as String? : null;
      final ownerId = spotRow != null ? spotRow['owner_id'] as String? : null;

      // 2. Fetch the owner's profile picture.
      String? profilePicUrl;
      if (ownerId != null && ownerId.isNotEmpty) {
        final ownerRow = await db
            .from('owners')
            .select('profile_picture_url')
            .eq('id', ownerId)
            .maybeSingle();
        final url = ownerRow?['profile_picture_url'] as String?;
        profilePicUrl = (url != null && url.isNotEmpty) ? url : null;
      }

      // 3. Check for an existing conversation.
      final userEmail = AuthService.currentUser?.email ?? '';
      final existing = await db
          .from('conversations')
          .select()
          .eq('customer_email', userEmail)
          .eq('study_spot_id', spotId)
          .maybeSingle();

      if (!context.mounted) return;

      if (existing != null) {
        final raw = existing;
        final conversation = Conversation(
          id: raw['id'] as String,
          studySpotId: raw['study_spot_id'] as String,
          reservationId: raw['reservation_id'] as String?,
          customerEmail: raw['customer_email'] as String,
          customerName: raw['customer_name'] as String?,
          lastMessage: raw['last_message'] as String?,
          lastMessageTime: raw['last_message_time'] != null
              ? DateTime.parse(raw['last_message_time'] as String).toLocal()
              : null,
          unread: raw['unread'] as bool? ?? false,
          createdAt: DateTime.parse(raw['created_at'] as String).toLocal(),
          studySpotName: spotName,
          profilePictureUrl: profilePicUrl, // ← owner's photo
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(conversation: conversation),
          ),
        );
      } else {
        _showFirstMessageDialog(
          context,
          spotId,
          reservationId,
          spotName,
          profilePicUrl,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open chat: $e',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ── First-message dialog ──────────────────────────────────────────────────
  void _showFirstMessageDialog(
    BuildContext context,
    String spotId,
    String reservationId,
    String? spotName,
    String? profilePicUrl,
  ) {
    final msgController = TextEditingController();
    bool sending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Message ${spotName ?? 'Study Spot'}',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: msgController,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Type your message to the study spot...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: GoogleFonts.inter(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: sending
                  ? null
                  : () async {
                      final text = msgController.text.trim();
                      if (text.isEmpty) return;
                      setDialogState(() => sending = true);
                      try {
                        // createNewConversation returns a bare Conversation
                        // without studySpotName — inject it manually.
                        final raw = await ChatService.createNewConversation(
                          studySpotId: spotId,
                          reservationId: reservationId,
                          firstMessage: text,
                        );
                        final conversation = Conversation(
                          id: raw.id,
                          studySpotId: raw.studySpotId,
                          reservationId: raw.reservationId,
                          customerEmail: raw.customerEmail,
                          customerName: raw.customerName,
                          lastMessage: raw.lastMessage,
                          lastMessageTime: raw.lastMessageTime,
                          unread: raw.unread,
                          createdAt: raw.createdAt,
                          studySpotName: spotName,
                          profilePictureUrl: profilePicUrl, // ← owner's photo
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatRoomScreen(conversation: conversation),
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => sending = false);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Failed to send: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Send',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  } // end _showFirstMessageDialog

  // ── Cancel dialog ─────────────────────────────────────────────────────────
  void _showCancelDialog(BuildContext context, String reservationId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Reservation?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          'Are you sure you want to cancel this booking? '
          'This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: Colors.black54,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep Booking',
              style: GoogleFonts.inter(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () async {
              Navigator.pop(ctx);

              try {
                await ReservationService.cancelReservation(reservationId);

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Reservation Cancelled Successfully',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Failed to cancel: $e',
                      style: GoogleFonts.inter(color: Colors.white),
                    ),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Review dialog ─────────────────────────────────────────────────────────
  void _showReviewDialog(
    BuildContext context,
    String reservationId,
    String spotId,
  ) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatingDialog(studySpotId: spotId),
    );
  }

  // ── Status colour ─────────────────────────────────────────────────────────
  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF3B82F6);
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'checked_in':
        return Colors.purple;
      default:
        return Colors.orange;
    }
  }

  // ── Status badge ──────────────────────────────────────────────────────────
  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status) {
      case 'confirmed':
        color = Colors.blue;
        break;
      case 'completed':
        color = Colors.green;
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      case 'checked_in':
        color = Colors.purple;
        break;
      default:
        color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No reservations yet.',
            style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Your booking history will appear here.',
            style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoRow
// ─────────────────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF3B82F6)),
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.grey[500],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
