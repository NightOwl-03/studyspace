import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/geofence_service.dart';
import '../services/reservation_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CheckedInScreen
// ─────────────────────────────────────────────────────────────────────────────
//
// Shown immediately after a reservation is confirmed.
// Receives a [GeofenceService] that is already monitoring the session.
//
// What's new vs the original:
//   • Displays a live grace-period warning banner with a countdown when
//     the user steps outside the 50 m geofence.
//   • Calls geofenceService.manualCheckout() when the user taps Check Out.
//   • Listens for onSessionEnded and onReservationAborted callbacks and
//     pops the screen automatically with appropriate feedback.
// ─────────────────────────────────────────────────────────────────────────────

class CheckedInScreen extends StatefulWidget {
  final String spotName;
  final String tableLabel;
  final List<String> seatLabels;
  final String reservationId;
  final String bookingReference; // ← the real DB-stored reference
  final GeofenceService geofenceService;
  final String startTime;
  final String? endTime;

  const CheckedInScreen({
    super.key,
    required this.spotName,
    required this.tableLabel,
    required this.seatLabels,
    required this.reservationId,
    required this.bookingReference,
    required this.startTime,
    this.endTime,
    required this.geofenceService,
  });

  @override
  State<CheckedInScreen> createState() => _CheckedInScreenState();
}

class _CheckedInScreenState extends State<CheckedInScreen> {
  // ── Grace period state ────────────────────────────────────────────────────
  bool _isGraceActive = false;
  int _graceRemainingSeconds = 0;

  // ── Checkout busy state ───────────────────────────────────────────────────
  bool _isCheckingOut = false;
  // ignore: unused_field
  bool _isCancelling = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Wire geofence callbacks.
    widget.geofenceService.onGracePeriodChange = _onGracePeriodChange;
    widget.geofenceService.onSessionEnded = _onSessionEnded;
    widget.geofenceService.onReservationAborted = _onReservationAborted;
  }

  @override
  void dispose() {
    // Clear callbacks so they don't fire on a dead widget.
    widget.geofenceService.onGracePeriodChange = null;
    widget.geofenceService.onSessionEnded = null;
    widget.geofenceService.onReservationAborted = null;
    super.dispose();
  }

  // ── Geofence callbacks ────────────────────────────────────────────────────

  void _onGracePeriodChange(bool isActive, int remainingSeconds) {
    if (!mounted) return;
    setState(() {
      _isGraceActive = isActive;
      _graceRemainingSeconds = remainingSeconds;
    });
  }

  void _onSessionEnded() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Your session has ended. Thanks for studying!',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    // Pop back to home.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onReservationAborted() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.red,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Reservation Aborted',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Your reservation was automatically cancelled due to a no-show. '
              'As a penalty, you are restricted from making new '
              'bookings for 3 hours.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                'Got it',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual checkout ───────────────────────────────────────────────────────

  Future<void> _checkout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Check Out?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This will end your session and release your seat. Are you sure?',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Check Out',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isCheckingOut = true);
    await widget.geofenceService.manualCheckout();
    // onSessionEnded callback will handle the pop.
    if (mounted) setState(() => _isCheckingOut = false);
  }

  // ── Cancel reservation ───────────────────────────────────────────────────

  // ignore: unused_element
  Future<void> _cancelReservation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Reservation?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep Booking',
              style: GoogleFonts.inter(
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isCancelling = true);

    try {
      // Stop geofence monitoring first so no callbacks fire during cancel.
      widget.geofenceService.stopMonitoring();

      await ReservationService.cancelReservation(widget.reservationId);

      if (!mounted) return;

      // Show success feedback then pop to home.
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

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
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
  }

  // ── Grace period countdown label ─────────────────────────────────────────

  String get _graceCountdownLabel {
    final minutes = _graceRemainingSeconds ~/ 60;
    final seconds = _graceRemainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'You\'re Checked In',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isCheckingOut)
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
              onPressed: _checkout,
              child: Text(
                'Check Out',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Grace period warning banner ──────────────────────────────────
          if (_isGraceActive) ...[
            _GracePeriodBanner(countdownLabel: _graceCountdownLabel),
            const SizedBox(height: 20),
          ],

          // ── Confirmation card ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Seat Reserved!',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.spotName,
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Details card ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session Details',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _DetailRow(
                  icon: Icons.confirmation_number_rounded,
                  label: 'Booking Reference',
                  value: '#${widget.bookingReference}',
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.table_restaurant_rounded,
                  label: 'Table',
                  value: widget.tableLabel,
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.event_seat_rounded,
                  label: widget.seatLabels.length == 1 ? 'Seat' : 'Seats',
                  value: widget.seatLabels.join(', '),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.login_rounded,
                  label: 'Check-in Time',
                  value: widget.startTime,
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.logout_rounded,
                  label: 'Expected Check-out',
                  value: widget.endTime ?? 'Flexible',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Geofence info card ───────────────────────────────────────────
          _GeofenceInfoCard(isGraceActive: _isGraceActive),

          const SizedBox(height: 32),

          // ── Check out button ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isCheckingOut ? null : _checkout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                'Check Out Early',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grace period warning banner
// ─────────────────────────────────────────────────────────────────────────────

class _GracePeriodBanner extends StatelessWidget {
  final String countdownLabel;
  const _GracePeriodBanner({required this.countdownLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.timer_rounded,
              color: Colors.orange,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You left the study spot!',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Return within $countdownLabel or your seat will be released.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Geofence info card (static info about how monitoring works)
// ─────────────────────────────────────────────────────────────────────────────

class _GeofenceInfoCard extends StatelessWidget {
  final bool isGraceActive;
  const _GeofenceInfoCard({required this.isGraceActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.my_location_rounded,
                color: Color(0xFF3B82F6),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Auto check-in is active',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isGraceActive
                ? 'You have stepped outside the 50 m zone. '
                      'Return soon — your seat is still held for now.'
                : 'Your GPS is being monitored within a 50 m radius of the spot. '
                      'Leaving for more than 15 minutes will automatically release your seat.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF1D4ED8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail row helper
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF3B82F6)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
