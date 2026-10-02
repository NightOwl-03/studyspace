import 'dart:math';
import '../core/supabase_client.dart';
import '../models/reservation.dart';
import 'auth_service.dart';
import 'seat_service.dart';

/// Handles creating, cancelling, and fetching reservations.
class ReservationService {
  // ── Booking reference generator ──────────────────────────────────────────
  /// Generates an 8-character alphanumeric booking reference.
  /// e.g.  "A3F7B2C9"
  static String _generateBookingReference() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// [seatIds] — list of seat IDs the user selected.
  /// [tableId] — the table those seats belong to.
  ///
  /// Returns the newly created [Reservation].
  static Future<Reservation> createReservation({
    required String studySpotId,
    required String tableId,
    required List<String> seatIds,
    required DateTime reservationDate,
    required String startTime, // e.g. "14:00"
    String? endTime,
    String? specialRequests,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in.');

    // 1. Insert the reservation
    final reservationRow = await db
        .from('reservations')
        .insert({
          'user_id': userId,
          'study_spot_id': studySpotId,
          'reservation_date': reservationDate
              .toIso8601String()
              .split('T')
              .first,
          'start_time': startTime,
          'end_time': endTime,
          'number_of_seats': seatIds.length,
          'reservation_status': 'confirmed',
          'booking_reference': _generateBookingReference(),
          'special_requests': specialRequests,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final reservationId = reservationRow['id'] as String;

    // 2. Insert reservation_details for each seat.
    final details = seatIds
        .map(
          (seatId) => {
            'reservation_id': reservationId,
            'seat_id': seatId,
            'table_id': tableId,
          },
        )
        .toList();
    await db.from('reservation_details').insert(details);

    // 3. Mark each seat as 'reserved'.
    for (final seatId in seatIds) {
      await SeatService.updateSeatStatus(seatId: seatId, status: 'reserved');
    }

    // 4. Update the table status only when the full table is taken.
    final takenSeats =
        await db
                .from('seats')
                .select('id')
                .or('seat_status.eq.reserved,seat_status.eq.occupied')
                .eq('table_id', tableId)
            as List<dynamic>;

    final tableRow = await db
        .from('study_spot_tables')
        .select('seat_capacity')
        .eq('id', tableId)
        .single();

    final capacity = (tableRow['seat_capacity'] as num).toInt();
    final newTableStatus = takenSeats.length >= capacity
        ? 'occupied'
        : 'available';

    await db
        .from('study_spot_tables')
        .update({
          'table_status': newTableStatus,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', tableId);

    // 5. Decrement available_seats on the study spot
    await db.rpc(
      'decrement_available_seats',
      params: {'spot_id': studySpotId, 'amount': seatIds.length},
    );

    return Reservation.fromMap(reservationRow);
  }

  static Future<void> cancelReservation(String reservationId) async {
    final row = await db
        .from('reservations')
        .select('study_spot_id, number_of_seats, reservation_status')
        .eq('id', reservationId)
        .single();

    final status = row['reservation_status'] as String;
    if (status == 'completed' || status == 'cancelled') {
      throw Exception('Reservation cannot be cancelled (status: $status).');
    }

    final spotId = row['study_spot_id'] as String;
    final seatCount = (row['number_of_seats'] as num).toInt();

    // ✅ STEP 1: Update status FIRST — if this fails, nothing else runs
    await db
        .from('reservations')
        .update({
          'reservation_status': 'cancelled',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', reservationId)
        .select()
        .single();

    // STEP 2: Only release seats after status is confirmed updated
    final details =
        await db
                .from('reservation_details')
                .select('seat_id')
                .eq('reservation_id', reservationId)
            as List<dynamic>;

    for (final r in details) {
      await SeatService.updateSeatStatus(
        seatId: (r as Map<String, dynamic>)['seat_id'] as String,
        status: 'available',
      );
    }

    // STEP 3: Increment available_seats back
    await db.rpc(
      'increment_available_seats',
      params: {'spot_id': spotId, 'amount': seatCount},
    );
  }

  // ── Fetch User's Reservations ─────────────────────────────────────────────
  /// Returns all reservations for the signed-in user, newest first.
  static Future<List<Reservation>> fetchMyReservations() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return [];

    final rows =
        await db
                .from('reservations')
                .select()
                .eq('user_id', userId)
                .order('created_at', ascending: false)
            as List<dynamic>;

    return rows
        .map((r) => Reservation.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
