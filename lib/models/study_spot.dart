/// Maps to public.study_spots table.
class StudySpot {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String locationAddress;
  final double latitude;
  final double longitude;
  final String city;
  final String? phoneNumber;
  final String? email;
  final String? openingTime; // stored as "HH:mm:ss" from Postgres time type
  final String? closingTime;
  final int totalSeats;
  final int availableSeats;
  final Map<String, dynamic> amenities;
  final List<String> imageUrls;
  final double averageRating;
  final int totalReviews;
  final String status;
  final bool isVerified;
  final bool
  isOpen; // From RPC: calculated based on current_time vs opening/closing
  final double
  weightedScore; // From RPC: weighted score based on availability, wifi, outlets
  final double distance; // From RPC: distance in meters from user location

  const StudySpot({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    required this.locationAddress,
    required this.latitude,
    required this.longitude,
    required this.city,
    this.phoneNumber,
    this.email,
    this.openingTime,
    this.closingTime,
    required this.totalSeats,
    required this.availableSeats,
    required this.amenities,
    required this.imageUrls,
    required this.averageRating,
    required this.totalReviews,
    required this.status,
    required this.isVerified,
    this.isOpen = true,
    this.weightedScore = 0.0,
    this.distance = 0.0,
  });

  /// Seats that are currently occupied / reserved.
  int get seatsUsed => totalSeats - availableSeats;

  /// 0.0 – 1.0 progress for LinearProgressIndicator.
  double get occupancyRate => totalSeats > 0 ? seatsUsed / totalSeats : 0.0;

  String? get firstImageUrl => imageUrls.isNotEmpty ? imageUrls.first : null;

  String get address => locationAddress;

  String get spotType {
    return (amenities['spot_type'] as String?) ??
        (amenities['type'] as String?) ??
        'cafe';
  }

  double? get wifiRating {
    final raw = amenities['wifi_rating'] ?? amenities['wifi'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  double? get minimumSpend {
    final raw = amenities['minimum_spend'] ?? amenities['min_spend'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  factory StudySpot.fromMap(Map<String, dynamic> map) {
    // image_urls comes as a Postgres array → List<dynamic>
    final rawImages = map['image_urls'];
    final images = rawImages is List
        ? rawImages.map((e) => e.toString()).toList()
        : <String>[];

    // amenities is jsonb → already decoded to Map by supabase_flutter
    final rawAmenities = map['amenities'];
    final amenities = rawAmenities is Map<String, dynamic>
        ? rawAmenities
        : <String, dynamic>{};

    return StudySpot(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      locationAddress: map['location_address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      city: map['city'] as String? ?? 'Digos City',
      phoneNumber: map['phone_number'] as String?,
      email: map['email'] as String?,
      openingTime: map['opening_time'] as String?,
      closingTime: map['closing_time'] as String?,
      totalSeats: (map['total_seats'] as num).toInt(),
      availableSeats: (map['available_seats'] as num?)?.toInt() ?? 0,
      amenities: amenities,
      imageUrls: images,
      averageRating: (map['average_rating'] as num?)?.toDouble() ?? 0.0,
      totalReviews: (map['total_reviews'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'active',
      isVerified: map['is_verified'] as bool? ?? false,
      isOpen: map['is_open'] as bool? ?? true,
      weightedScore: (map['weighted_score'] as num?)?.toDouble() ?? 0.0,
      distance: (map['distance_meters'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
