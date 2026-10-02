import '../core/supabase_client.dart';
import '../models/seat.dart';

class SeatService {
  static Future<List<StudySpotTable>> fetchTablesWithSeats(
    String studySpotId,
  ) async {
    final data = await db
        .from('study_spot_tables')
        .select('*, seats(*)')
        .eq('study_spot_id', studySpotId);

    return (data).map((row) => StudySpotTable.fromMap(row)).toList();
  }

  static Stream<List<Seat>> seatsStream(String tableId) {
    return db
        .from('seats')
        .stream(primaryKey: ['id'])
        .eq('table_id', tableId)
        .map((rows) => rows.map((row) => Seat.fromMap(row)).toList());
  }

  static Future<void> updateSeatStatus({
    required String seatId,
    required String status,
  }) async {
    await db
        .from('seats')
        .update({
          'seat_status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', seatId);
  }

  static Future<void> updateSeatsStatus({
    required List<String> seatIds,
    required String status,
  }) async {
    if (seatIds.isEmpty) return;

    await db
        .from('seats')
        .update({
          'seat_status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', seatIds);
  }

  static Future<void> syncSeatsForReservation({
    required String reservationId,
    required String reservationStatus,
  }) async {
    const statusMap = {
      'pending': 'reserved',
      'confirmed': 'reserved',
      'checked_in': 'occupied',
      'completed': 'available',
      'cancelled': 'available',
    };

    final seatStatus = statusMap[reservationStatus];
    if (seatStatus == null) return;

    // Fetch assigned seat IDs from reservation_details
    final details = await db
        .from('reservation_details')
        .select('seat_id')
        .eq('reservation_id', reservationId);

    if ((details as List).isEmpty) return;

    final seatIds = details.map((row) => row['seat_id'] as String).toList();

    await updateSeatsStatus(seatIds: seatIds, status: seatStatus);
  }
}
