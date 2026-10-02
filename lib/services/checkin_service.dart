import '../core/supabase_client.dart';
import 'auth_service.dart';
import 'seat_service.dart';

/// Handles check-in and check-out operations.
/// A check-in record is written to public.check_ins and
/// the seat status is updated to 'occupied'.
class CheckInService {
  // ── Check In ──────────────────────────────────────────────────────────────
  /// Records a check-in for the current user.
  /// Marks the seat as 'occupied' and awards points.
  ///
  /// Returns the check-in row ID.
  static Future<String> checkIn({
    required String studySpotId,
    required String seatId,
    required String tableId,
    String? reservationId,
    int pointsToAward = 10,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in.');

    final now = DateTime.now().toIso8601String();

    // 1. Insert check-in record
    final row = await db
        .from('check_ins')
        .insert({
          'user_id': userId,
          'study_spot_id': studySpotId,
          'reservation_id': reservationId,
          'table_id': tableId,
          'seat_id': seatId,
          'check_in_time': now,
          'is_verified': true,
          'points_earned': pointsToAward,
          'created_at': now,
        })
        .select('id')
        .single();

    final checkInId = row['id'] as String;

    // 2. Mark the seat as occupied
    await SeatService.updateSeatStatus(seatId: seatId, status: 'occupied');

    // 3. Award points to the user
    await _awardPoints(
      userId: userId,
      checkInId: checkInId,
      points: pointsToAward,
      description: 'Points earned from check-in',
    );

    return checkInId;
  }

  // ── Check Out ─────────────────────────────────────────────────────────────
  /// Records check-out time and duration, then releases the seat.
  static Future<void> checkOut({
    required String checkInId,
    required String seatId,
    required String studySpotId,
  }) async {
    final checkOutTime = DateTime.now();

    // 1. Fetch check-in time to calculate duration
    final row =
        await db
                .from('check_ins')
                .select('check_in_time')
                .eq('id', checkInId)
                .single();

    final checkInTime = DateTime.parse(row['check_in_time'] as String);
    final durationMinutes = checkOutTime.difference(checkInTime).inMinutes;

    // 2. Update check-in row with check-out info
    await db
        .from('check_ins')
        .update({
          'check_out_time': checkOutTime.toIso8601String(),
          'duration_minutes': durationMinutes,
        })
        .eq('id', checkInId);

    // 3. Release the seat
    await SeatService.updateSeatStatus(seatId: seatId, status: 'available');

    // 4. Increment available_seats on the study spot
    await db.rpc(
      'increment_available_seats',
      params: {'spot_id': studySpotId, 'amount': 1},
    );
  }

  // ── Internal: Award Points ────────────────────────────────────────────────
  static Future<void> _awardPoints({
    required String userId,
    required String checkInId,
    required int points,
    required String description,
  }) async {
    // Fetch current balance
    final userData = await db.from('users').select('total_points').eq('id', userId).single();

    final currentPoints = (userData['total_points'] as num?)?.toInt() ?? 0;
    final newBalance = currentPoints + points;

    // Insert points_transactions row
    await db.from('points_transactions').insert({
      'user_id': userId,
      'transaction_type': 'earned_checkin',
      'amount': points,
      'description': description,
      'related_checkin_id': checkInId,
      'balance_after': newBalance,
      'transaction_date': DateTime.now().toIso8601String(),
    });

    // Update total_points in users
    await db
        .from('users')
        .update({
          'total_points': newBalance,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }
}
