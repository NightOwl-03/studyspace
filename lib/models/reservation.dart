/// Maps to public.reservations table.
class Reservation {
  final String id;
  final String userId;
  final String studySpotId;
  final DateTime reservationDate;
  final String startTime;
  final String? endTime;
  final int numberOfSeats;
  final String
  status; // pending | confirmed | checked_in | completed | cancelled
  final String? specialRequests;
  final String? bookingReference;
  final DateTime createdAt;

  const Reservation({
    required this.id,
    required this.userId,
    required this.studySpotId,
    required this.reservationDate,
    required this.startTime,
    this.endTime,
    required this.numberOfSeats,
    required this.status,
    this.specialRequests,
    this.bookingReference,
    required this.createdAt,
  });

  bool get isCancellable => status == 'pending' || status == 'confirmed';

  factory Reservation.fromMap(Map<String, dynamic> map) {
    return Reservation(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      studySpotId: map['study_spot_id'] as String,
      reservationDate: DateTime.parse(map['reservation_date'] as String),
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String?,
      numberOfSeats: (map['number_of_seats'] as num).toInt(),
      status: map['reservation_status'] as String? ?? 'pending',
      specialRequests: map['special_requests'] as String?,
      bookingReference: map['booking_reference'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
