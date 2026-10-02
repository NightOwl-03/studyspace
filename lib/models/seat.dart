/// Maps to public.seats table.
class Seat {
  final String id;
  final String tableId;
  final String seatNumber;
  final String
  seatStatus; // 'available' | 'occupied' | 'reserved' | 'maintenance'

  const Seat({
    required this.id,
    required this.tableId,
    required this.seatNumber,
    required this.seatStatus,
  });

  bool get isAvailable => seatStatus == 'available';

  factory Seat.fromMap(Map<String, dynamic> map) {
    return Seat(
      id: _stringify(map['id']),
      tableId: _stringify(map['table_id']),
      seatNumber: _stringify(map['seat_number']),
      seatStatus: _stringify(map['seat_status']).toLowerCase().isEmpty
          ? 'available'
          : _stringify(map['seat_status']).toLowerCase(),
    );
  }
}

/// Maps to public.study_spot_tables table,
/// with its nested seats list.
class StudySpotTable {
  final String id;
  final String studySpotId;
  final String tableNumber;
  final int seatCapacity;
  final String tableStatus;
  final List<Seat> seats;

  const StudySpotTable({
    required this.id,
    required this.studySpotId,
    required this.tableNumber,
    required this.seatCapacity,
    required this.tableStatus,
    required this.seats,
  });

  bool get isAvailable => tableStatus == 'available';

  factory StudySpotTable.fromMap(Map<String, dynamic> map) {
    // seats is a nested list from the join query
    final rawSeats = map['seats'] as List? ?? [];
    final seats = rawSeats
        .map((s) => Seat.fromMap(s as Map<String, dynamic>))
        .toList();

    return StudySpotTable(
      id: _stringify(map['id']),
      studySpotId: _stringify(map['study_spot_id']),
      tableNumber: _stringify(map['table_number']),
      seatCapacity: (map['seat_capacity'] as num).toInt(),
      tableStatus: _stringify(map['table_status']).toLowerCase().isEmpty
          ? 'available'
          : _stringify(map['table_status']).toLowerCase(),
      seats: seats,
    );
  }
}

String _stringify(dynamic value) {
  if (value == null) return '';
  return value.toString();
}
