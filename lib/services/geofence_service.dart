import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../core/supabase_client.dart';
import '../models/study_spot.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeofenceService
// ─────────────────────────────────────────────────────────────────────────────
//
// Drives the full automated session lifecycle for a single reservation:
//
//   Reserved ──(enter 50 m geofence)──► Occupied / checked_in
//   Occupied ──(leave geofence)──► Grace Period (15 min)
//   Grace    ──(return in time)──► Occupied (timer cancelled)
//   Grace    ──(timer expires)──► Available  (seat released, session complete)
//   Reserved ──(no entry >30 min after start_time)──► Aborted + 24 h ban
//
// Usage:
//   final svc = GeofenceService();
//   svc.onGracePeriodChange = (active, remaining) { setState(...); };
//   svc.startMonitoring(reservation, spot);
//   // later:
//   svc.stopMonitoring();
//
// pubspec.yaml dependency already present: geolocator
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight data class passed to GeofenceService.
/// Mirrors what ReservationService.createReservation() returns.
class ActiveReservation {
  final String id;
  final String userId;
  final String studySpotId;
  final DateTime startDateTime; // reservation_date + start_time combined
  final List<String> seatIds;

  const ActiveReservation({
    required this.id,
    required this.userId,
    required this.studySpotId,
    required this.startDateTime,
    required this.seatIds,
  });
}

/// Callback signature: (isGraceActive, remainingSeconds)
typedef GracePeriodCallback =
    void Function(bool isActive, int remainingSeconds);

class GeofenceService {
  // ── Constants ────────────────────────────────────────────────────────────
  static const double geofenceRadiusMeters = 50.0;
  static const Duration gracePeriodDuration = Duration(minutes: 15);
  static const Duration noShowWindow = Duration(minutes: 30);

  // How often to tick the grace-period countdown for UI updates
  static const Duration _graceTick = Duration(seconds: 10);

  // ── Internal state ───────────────────────────────────────────────────────
  ActiveReservation? _reservation;
  StudySpot? _spot;

  bool _isCheckedIn = false;
  bool _isInsideGeofence = false;
  bool _isGraceActive = false;
  DateTime? _gracePeriodStartedAt;

  Timer? _noShowTimer;
  Timer? _gracePeriodTimer;
  Timer? _graceTickTimer; // fires every 10 s to update UI countdown
  StreamSubscription<Position>? _positionStream;

  // ── Public callbacks (wire these up in CheckedInScreen) ──────────────────

  /// Called whenever the grace period starts, ticks, or ends.
  /// [isActive] false + [remainingSeconds] 0 means grace period expired.
  GracePeriodCallback? onGracePeriodChange;

  /// Called when the session is fully ended (grace expired or manual checkout).
  VoidCallback? onSessionEnded;

  /// Called when the reservation is aborted (no-show).
  VoidCallback? onReservationAborted;

  // ── Entry point ──────────────────────────────────────────────────────────

  /// Call immediately after a reservation is confirmed.
  /// Safe to call multiple times — cleans up any prior monitoring first.
  void startMonitoring(ActiveReservation reservation, StudySpot spot) {
    stopMonitoring(); // clean slate
    _reservation = reservation;
    _spot = spot;
    _isCheckedIn = false;
    _isInsideGeofence = false;
    _isGraceActive = false;

    _startNoShowWatchdog();
    _startPositionStream();
  }

  // ── No-show watchdog ─────────────────────────────────────────────────────

  void _startNoShowWatchdog() {
    final res = _reservation!;
    // Deadline = user's chosen start_time + 30 minutes.
    // e.g. if reserved for 4:00 PM the watchdog fires at 4:30 PM.
    final noShowDeadline = res.startDateTime.add(noShowWindow);
    final timeUntilDeadline = noShowDeadline.difference(DateTime.now());

    // If the deadline is already in the past (e.g. app reopened late),
    // fire immediately on the next event-loop tick instead of scheduling
    // a negative timer, which would fire instantly anyway but is cleaner.
    final delay = timeUntilDeadline.isNegative
        ? Duration.zero
        : timeUntilDeadline;

    _noShowTimer = Timer(delay, () async {
      if (!_isCheckedIn) {
        await _handleNoShow(); // Trigger 3-hour penalty
      }
    });
  }

  // ── GPS position stream ──────────────────────────────────────────────────

  void _startPositionStream() {
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            // Only emit when user moves ≥10 m — avoids GPS jitter re-triggering logic.
            distanceFilter: 10,
          ),
        ).listen(
          _onPositionUpdate,
          onError: (_) {
            // GPS error — do nothing; last known state persists.
          },
        );
  }

  // ── Position update handler ──────────────────────────────────────────────

  void _onPositionUpdate(Position position) {
    final spot = _spot;
    if (spot == null) return;

    final distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      spot.latitude,
      spot.longitude,
    );

    final nowInside = distanceMeters <= geofenceRadiusMeters;

    if (nowInside && !_isInsideGeofence) {
      _isInsideGeofence = true;
      _handleGeofenceEnter();
    } else if (!nowInside && _isInsideGeofence) {
      _isInsideGeofence = false;
      _handleGeofenceExit();
    }
  }

  // ── Geofence enter: Reserved → Occupied ─────────────────────────────────

  void _handleGeofenceEnter() async {
    // Cancel no-show watchdog — user arrived in time.
    _noShowTimer?.cancel();
    _noShowTimer = null;

    // If grace period was running (user stepped out and came back) — cancel it.
    if (_isGraceActive) {
      _cancelGracePeriod();
      onGracePeriodChange?.call(false, 0);
      // Seat stays 'occupied' in DB — no write needed.
      return;
    }

    // Idempotent: only promote once.
    if (_isCheckedIn) return;
    _isCheckedIn = true;

    final res = _reservation!;

    // 1. Update reservation status → checked_in
    await db
        .from('reservations')
        .update({
          'reservation_status': 'checked_in',
          'geofence_entered_at': DateTime.now().toIso8601String(),
        })
        .eq('id', res.id);

    // 2. Mark seats occupied
    for (final seatId in res.seatIds) {
      await db
          .from('seats')
          .update({'seat_status': 'occupied'})
          .eq('id', seatId);
    }
  }

  // ── Geofence exit: start grace period ───────────────────────────────────

  void _handleGeofenceExit() async {
    // Only applies once checked in.
    if (!_isCheckedIn) return;
    // Don't double-start the timer.
    if (_isGraceActive) return;

    _isGraceActive = true;
    _gracePeriodStartedAt = DateTime.now();

    // Record in DB so the server-side cron can recover if app is killed.
    await db
        .from('reservations')
        .update({
          'grace_period_started_at': _gracePeriodStartedAt!.toIso8601String(),
        })
        .eq('id', _reservation!.id);

    // Emit initial callback.
    onGracePeriodChange?.call(true, gracePeriodDuration.inSeconds);

    // Start countdown timer that expires in 15 minutes.
    _gracePeriodTimer = Timer(gracePeriodDuration, _handleGracePeriodExpired);

    // Tick every 10 s so the UI shows a live countdown.
    _graceTickTimer = Timer.periodic(_graceTick, (_) {
      if (!_isGraceActive) return;
      final elapsed = DateTime.now().difference(_gracePeriodStartedAt!);
      final remaining = gracePeriodDuration - elapsed;
      final remainingSeconds = remaining.inSeconds.clamp(
        0,
        gracePeriodDuration.inSeconds,
      );
      onGracePeriodChange?.call(true, remainingSeconds);
    });
  }

  // ── Grace period expired: release seat ──────────────────────────────────

  Future<void> _handleGracePeriodExpired() async {
    _isGraceActive = false;

    final res = _reservation!;

    // 1. Complete the reservation.
    await db
        .from('reservations')
        .update({'reservation_status': 'completed'})
        .eq('id', res.id);

    // 2. Release seats.
    for (final seatId in res.seatIds) {
      await db
          .from('seats')
          .update({'seat_status': 'available'})
          .eq('id', seatId);
    }

    // 3. Notify UI.
    onGracePeriodChange?.call(false, 0);
    onSessionEnded?.call();

    stopMonitoring();
  }

  // ── No-show: abort + ban ─────────────────────────────────────────────────

  Future<void> _handleNoShow() async {
    final res = _reservation;
    if (res == null) return;

    // 1. Mark reservation as 'cancelled'.
    //    geofence_entered_at will be NULL because the user never arrived —
    //    the Supabase trigger uses this to distinguish a no-show cancellation
    //    from a manual user cancellation and inserts the 3-hour ban + notification.
    await db
        .from('reservations')
        .update({'reservation_status': 'cancelled'})
        .eq('id', res.id);

    // 2. Release the seats so other users can book them.
    for (final seatId in res.seatIds) {
      await db
          .from('seats')
          .update({'seat_status': 'available'})
          .eq('id', seatId);
    }

    // 3. The ban insert and user notification are handled automatically by
    //    the Supabase SQL trigger `trg_no_show_penalty` — no manual DB
    //    writes needed here.

    onReservationAborted?.call();
    stopMonitoring();
  }

  // ── Manual checkout (called by CheckedInScreen "Check Out" button) ───────

  /// Call this when the user manually checks out from CheckedInScreen.
  /// Completes the reservation gracefully without any penalty.
  Future<void> manualCheckout() async {
    final res = _reservation;
    if (res == null) return;

    // Release any running timers first.
    _cancelGracePeriod();
    _noShowTimer?.cancel();

    await db
        .from('reservations')
        .update({'reservation_status': 'completed'})
        .eq('id', res.id);

    for (final seatId in res.seatIds) {
      await db
          .from('seats')
          .update({'seat_status': 'available'})
          .eq('id', seatId);
    }

    onSessionEnded?.call();
    stopMonitoring();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _cancelGracePeriod() {
    _isGraceActive = false;
    _gracePeriodStartedAt = null;
    _gracePeriodTimer?.cancel();
    _gracePeriodTimer = null;
    _graceTickTimer?.cancel();
    _graceTickTimer = null;
  }

  /// Stops all timers and GPS streams. Safe to call multiple times.
  void stopMonitoring() {
    _positionStream?.cancel();
    _positionStream = null;
    _noShowTimer?.cancel();
    _noShowTimer = null;
    _cancelGracePeriod();
    _reservation = null;
    _spot = null;
  }

  // ── Ban check (called before createReservation) ──────────────────────────

  /// Returns null if the user is not banned.
  /// Returns a human-readable message if they are.
  static Future<String?> checkBanStatus(String userId) async {
    final now = DateTime.now().toIso8601String();

    final ban = await db
        .from('user_bans')
        .select()
        .eq('user_id', userId)
        .eq('is_active', true)
        .gt('expires_at', now)
        .order('expires_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (ban == null) return null;

    final expiresAt = DateTime.parse(ban['expires_at'] as String);
    final remaining = expiresAt.difference(DateTime.now());

    // Friendly reminder for the 3-hour cooling period
    return 'You are restricted from making reservations because of a previous no-show. '
        'Restriction lifts in ${remaining.inHours}h ${remaining.inMinutes % 60}m.';
  }
}
