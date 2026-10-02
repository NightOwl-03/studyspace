/// Represents a spot fetched from the OpenStreetMap Overpass API.
///
/// Covers three distinct place types found in Digos City:
///   • 'cafe'       — amenity=cafe
///   • 'library'    — amenity=library
///   • 'study_hub'  — office=coworking, or name contains "Study Hub",
///                    or a manually-injected community favourite.
///
/// Simulated real-time fields ([seatAvailability], [wifiSpeed],
/// [outletCount]) are injected by [OsmCafeService] so they can be
/// passed directly into the same weighted-scoring algorithm that
/// powers [StudySpotService._applyClientScoring]:
///
///   final_score = (seatAvailability * 0.50)
///               + (wifiSpeed       * 0.30)
///               + (outletCount     * 0.20)
///
/// All three fields are normalised to the [0.0 – 1.0] range.
class CafeModel {
  // ── Core identity ─────────────────────────────────────────────────────────

  /// OSM element id (e.g. "node/12345678"), or "manual/<slug>" for injected
  /// spots. Unique and stable across the session.
  final String id;

  /// Display name from OSM `name` tag.  Falls back to "Unnamed Cafe".
  final String name;

  // ── Spot classification ───────────────────────────────────────────────────

  /// One of: 'cafe', 'library', 'study_hub'.
  /// Derived by [OsmCafeService._resolveSpotType] from OSM tags and/or name.
  final String spotType;

  // ── Location ──────────────────────────────────────────────────────────────

  final double latitude;
  final double longitude;

  /// Human-readable address assembled from OSM addr:* tags.
  /// May be 'Digos City' if OSM has no address data for this node.
  final String address;

  // ── Simulated real-time metrics (0.0 – 1.0) ──────────────────────────────

  /// Fraction of seats that are currently available.
  /// 1.0 = completely empty, 0.0 = completely full.
  final double seatAvailability;

  /// Normalised Wi-Fi speed score.
  /// 1.0 = excellent, 0.0 = no Wi-Fi.
  final double wifiSpeed;

  /// Normalised outlet availability score.
  /// 1.0 = outlets at every seat, 0.0 = no outlets.
  final double outletCount;

  // ── Computed weighted score ───────────────────────────────────────────────

  /// Pre-computed score using the same 50/30/20 formula as StudySpotService.
  /// Higher is better.
  final double weightedScore;

  // ── Visuals ───────────────────────────────────────────────────────────────

  /// A stock or curated photo URL assigned by [OsmCafeService].
  final String imageUrl;

  // ── Optional OSM extras ───────────────────────────────────────────────────

  /// Raw tags map from the Overpass response (or synthetic tags for manual
  /// spots). Useful for displaying extras (opening_hours, phone, website,
  /// spot_type) without re-fetching from the API.
  final Map<String, String> osmTags;

  // ── Simulated open status ─────────────────────────────────────────────────

  /// Whether the spot is currently open.
  /// Simulated deterministically (~70% open, ~30% closed) by [OsmCafeService].
  final bool isOpen;

  // ── Real distance from user ───────────────────────────────────────────────

  /// Distance in meters from the user's current location to this spot.
  /// Computed using the Haversine formula in [OsmCafeService].
  final double distanceMeters;

  // ── Constructor ───────────────────────────────────────────────────────────

  const CafeModel({
    required this.id,
    required this.name,
    required this.spotType,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.seatAvailability,
    required this.wifiSpeed,
    required this.outletCount,
    required this.weightedScore,
    required this.imageUrl,
    required this.osmTags,
    required this.isOpen,
    required this.distanceMeters,
  });

  // ── Derived helpers ───────────────────────────────────────────────────────

  String? get openingHours => osmTags['opening_hours'];
  String? get phone => osmTags['phone'] ?? osmTags['contact:phone'];
  String? get website => osmTags['website'] ?? osmTags['contact:website'];

  /// Converts to [StudySpot]-compatible amenities map so the two data
  /// sources can share the same scoring/rendering logic.
  Map<String, dynamic> toAmenitiesMap() => {
    'spot_type': spotType,
    'wifi_rating': (wifiSpeed * 5).toStringAsFixed(1),
    'outlets': (outletCount * 10).toStringAsFixed(0),
  };

  // ── Debug ─────────────────────────────────────────────────────────────────

  @override
  String toString() =>
      'CafeModel(id: $id, name: $name, type: $spotType, score: ${weightedScore.toStringAsFixed(2)})';
}
