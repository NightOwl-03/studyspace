import 'dart:async';
import 'dart:convert';
import 'dart:io'; // ← required for SocketException
import 'dart:math';
import 'package:http/http.dart' as http;

import '../models/cafe_model.dart';

/// Fetches cafes, libraries, and study hubs from the OpenStreetMap Overpass
/// API for Digos City, enriches them with simulated real-time metrics, injects
/// manually-curated community favourites, and returns a weighted-score-sorted
/// [List<CafeModel>] ready for flutter_map markers.
///
/// ── Spot types returned ───────────────────────────────────────────────────
///   • 'cafe'       — amenity=cafe nodes/ways
///   • 'library'    — amenity=library nodes/ways
///   • 'study_hub'  — office=coworking nodes/ways, any node whose name
///                    contains "Study Hub" (case-insensitive), and the three
///                    manually-injected Digos community favourites.
///
/// ── Pipeline ─────────────────────────────────────────────────────────────
///  1. Query Overpass API  →  raw OSM nodes/ways (cafes + libraries + coworking)
///  2. Filter             →  exclude names matching [_excluded] (null-safe)
///  3. Classify           →  assign spotType via [_resolveSpotType]
///  4. Enrich             →  inject simulated seatAvailability/wifiSpeed/outletCount
///  5. Assign image       →  curated or type-appropriate stock photo
///  6. Score & sort       →  50% seats + 30% wifi + 20% outlets, descending
///  7. Inject manual      →  prepend [_buildManualSpots] community favourites
/// ─────────────────────────────────────────────────────────────────────────
class OsmCafeService {
  // ── Overpass configuration ────────────────────────────────────────────────

  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';

  /// Bounding box for Digos City: south, west, north, east (Overpass format).
  /// Expanded to cover the full city area including surrounding barangays.
  static const String _bbox = '6.72,125.33,6.80,125.40';

  /// Expanded Overpass QL query covering:
  ///   • amenity=cafe          — coffee shops
  ///   • amenity=library       — public libraries
  ///   • office=coworking      — coworking spaces
  ///   • name~"Study Hub",i    — any node/way whose name contains "Study Hub"
  ///
  /// `[out:json]` must come first.
  /// `out center tags` is required so way elements receive a synthetic lat/lon.
  static const String _query =
      '''[out:json];
(
  node["amenity"="cafe"]($_bbox);
  way["amenity"="cafe"]($_bbox);
  node["amenity"="library"]($_bbox);
  way["amenity"="library"]($_bbox);
  node["office"="coworking"]($_bbox);
  way["office"="coworking"]($_bbox);
  node["name"~"Study Hub",i]($_bbox);
  way["name"~"Study Hub",i]($_bbox);
);
out center tags;''';

  // ── Filter list ───────────────────────────────────────────────────────────

  /// Case-insensitive partial-match names to exclude from OSM results because
  /// they are already tracked in the Supabase study_spots table.
  static const List<String> _excluded = ['green coffee'];

  // ── Named spot photo map ──────────────────────────────────────────────────

  /// Keys are lowercase partial name matches (checked via String.contains).
  /// Covers known Digos cafes, libraries, and study hubs.
  static const Map<String, String> _namedPhotos = {
    // ── Cafes ──────────────────────────────────────────────────────────────
    'green coffee':
        'https://images.unsplash.com/photo-1600093463592-8e36ae95ef56?w=800&q=80',
    'blugre':
        'https://images.unsplash.com/photo-1445116572660-236099ec97a0?w=800&q=80',
    'nook':
        'https://images.unsplash.com/photo-1559925393-8be0ec4767c8?w=800&q=80',
    'sooyop':
        'https://images.unsplash.com/photo-1585338107529-13afc5f02586?w=800&q=80',
    'cafelino':
        'https://images.unsplash.com/photo-1493857671505-72967e2e2760?w=800&q=80',
    'denise':
        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&q=80',
    'coffee cat':
        'https://images.unsplash.com/photo-1525610553991-2bede1a236e2?w=800&q=80',
    'frog':
        'https://images.unsplash.com/photo-1470337458703-46ad1756a187?w=800&q=80',
    'demitasse':
        'https://images.unsplash.com/photo-1511920170033-f8396924c348?w=800&q=80',
    'mysa':
        'https://images.unsplash.com/photo-1453614512568-c4024d13c247?w=800&q=80',
    'annipie':
        'https://images.unsplash.com/photo-1464983953574-0892a716854b?w=800&q=80',
    'lara mia':
        'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=800&q=80',

    // ── Libraries ─────────────────────────────────────────────────────────
    'library':
        'https://images.unsplash.com/photo-1507842217343-583bb7270b66?w=800&q=80',
    'national library':
        'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80',
    'public library':
        'https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?w=800&q=80',
    'city library':
        'https://images.unsplash.com/photo-1549383618-a5b66f3ad35a?w=800&q=80',

    // ── Study Hubs & Coworking ─────────────────────────────────────────────
    'focus point':
        'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=800&q=80',
    'dreamy desk':
        'https://images.unsplash.com/photo-1593642632559-0c6d3fc62b89?w=800&q=80',
    'minna':
        'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=800&q=80',
    'study hub':
        'https://images.unsplash.com/photo-1497366811353-6870744d04b2?w=800&q=80',
    'cowork':
        'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=800&q=80',
    'workspace':
        'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=800&q=80',
  };

  // ── Fallback stock photos per type ────────────────────────────────────────

  static const List<String> _cafeStockPhotos = [
    'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800&q=80',
    'https://images.unsplash.com/photo-1521017432531-fbd92d768814?w=800&q=80',
    'https://images.unsplash.com/photo-1509042239860-f550ce710b93?w=800&q=80',
    'https://images.unsplash.com/photo-1442512595331-e89e73853f31?w=800&q=80',
    'https://images.unsplash.com/photo-1600093463592-8e36ae95ef56?w=800&q=80',
  ];

  static const List<String> _libraryStockPhotos = [
    'https://images.unsplash.com/photo-1507842217343-583bb7270b66?w=800&q=80',
    'https://images.unsplash.com/photo-1521587760476-6c12a4b040da?w=800&q=80',
    'https://images.unsplash.com/photo-1524995997946-a1c2e315a42f?w=800&q=80',
    'https://images.unsplash.com/photo-1549383618-a5b66f3ad35a?w=800&q=80',
    'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80',
  ];

  static const List<String> _studyHubStockPhotos = [
    'https://images.unsplash.com/photo-1497366811353-6870744d04b2?w=800&q=80',
    'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?w=800&q=80',
    'https://images.unsplash.com/photo-1497366754035-f200968a6e72?w=800&q=80',
    'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=800&q=80',
    'https://images.unsplash.com/photo-1593642632559-0c6d3fc62b89?w=800&q=80',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Fetches all cafes, libraries, and coworking/study spots in Digos City
  /// from the Overpass API, applies filtering + enrichment + scoring, prepends
  /// manually-injected community favourites, and returns the sorted list.
  ///
  /// Throws typed [OsmFetchException] variants so the caller can display
  /// a specific message:
  ///   • [OsmNetworkException]  — SocketException / timeout (no internet)
  ///   • [OsmParseException]    — FormatException (bad / unexpected JSON)
  ///   • [OsmHttpException]     — non-200 HTTP status
  ///   • [OsmEmptyException]    — 200 but "elements" array is missing/empty
  static Future<List<CafeModel>> fetchExternalCafes({
    double userLatitude = 6.7490,
    double userLongitude = 125.3580,
  }) async {
    // Always pre-build manual spots so they show even when OSM fetch fails.
    final manualSpots = _buildManualSpots(userLatitude, userLongitude);

    List<dynamic> rawElements;
    try {
      rawElements = await _queryOverpass();
    } on OsmFetchException {
      // Network / HTTP / parse error — return just the manual spots so the
      // home screen and map always have at least the community favourites.
      return manualSpots;
    }

    final spots = <CafeModel>[];

    for (final element in rawElements) {
      final tags = _parseTags(element['tags']);

      final name = (tags['name'] ?? '').trim();
      final displayName = name.isEmpty ? 'Unnamed Spot' : name;

      // ── Filter: skip excluded names ────────────────────────────────────────
      if (_isExcluded(displayName)) continue;

      // ── Resolve coordinates ────────────────────────────────────────────────
      final double? lat = _resolveCoord(element, 'lat');
      final double? lon = _resolveCoord(element, 'lon');
      if (lat == null || lon == null) continue;

      // ── Build stable id ────────────────────────────────────────────────────
      final type = (element['type'] as String?) ?? 'node';
      final osmId = element['id']?.toString() ?? '';
      final id = '$type/$osmId';

      // ── Classify spot type ─────────────────────────────────────────────────
      final spotType = _resolveSpotType(tags, displayName);

      // ── Simulated real-time metrics ────────────────────────────────────────
      final seededRng = Random(_stableHash(id));
      final seatAvailability = _randomDouble(seededRng, min: 0.1, max: 1.0);
      final wifiSpeed = _randomDouble(seededRng, min: 0.0, max: 1.0);
      final outletCount = _randomDouble(seededRng, min: 0.0, max: 1.0);

      // ── Open status (deterministic ~70% open) ──────────────────────────────
      final isOpen = (_stableHash('${id}_open').abs() % 10) >= 3;

      // ── Distance from user ─────────────────────────────────────────────────
      final distanceMeters = _haversineDistance(
        userLatitude,
        userLongitude,
        lat,
        lon,
      );

      // ── Weighted score ─────────────────────────────────────────────────────
      final weightedScore =
          (seatAvailability * 0.50) + (wifiSpeed * 0.30) + (outletCount * 0.20);

      // ── Photo ──────────────────────────────────────────────────────────────
      final imageUrl = _resolvePhoto(displayName, id, spotType);

      // ── Address ────────────────────────────────────────────────────────────
      final address = _buildAddress(tags, displayName);

      // ── Store spot_type inside osmTags so it flows into amenities map ──────
      final enrichedTags = Map<String, String>.from(tags)
        ..['spot_type'] = spotType;

      spots.add(
        CafeModel(
          id: id,
          name: displayName,
          spotType: spotType,
          latitude: lat,
          longitude: lon,
          address: address,
          seatAvailability: seatAvailability,
          wifiSpeed: wifiSpeed,
          outletCount: outletCount,
          weightedScore: weightedScore,
          imageUrl: imageUrl,
          osmTags: enrichedTags,
          isOpen: isOpen,
          distanceMeters: distanceMeters,
        ),
      );
    }

    // ── Sort highest score first ───────────────────────────────────────────
    spots.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));

    // ── Prepend manually-injected community favourites ─────────────────────
    return [...manualSpots, ...spots];
  }

  // ── Manual community spot injection ───────────────────────────────────────

  /// Returns the three manually-curated Digos City study hubs.
  ///
  /// These spots are not (yet) in OSM, but are well-known community
  /// favourites. They are assigned deterministic metrics from their
  /// stable name-based hash so values are consistent across sessions.
  static List<CafeModel> _buildManualSpots(double userLat, double userLon) {
    const manualData = [
      (
        slug: 'focus-point-study-hub',
        name: 'Focus Point Study Hub',
        lat: 6.7493,
        lon: 125.3575,
        address: 'Quezon Avenue, Digos City, Davao del Sur',
      ),
      (
        slug: 'dreamy-desk',
        name: 'Dreamy Desk',
        lat: 6.7485,
        lon: 125.3590,
        address: 'JP Laurel Street, Digos City, Davao del Sur',
      ),
      (
        slug: 'minna-study-hub',
        name: 'Minna Study Hub',
        lat: 6.7499,
        lon: 125.3565,
        address: 'Rizal Avenue, Digos City, Davao del Sur',
      ),
    ];

    return manualData.map((d) {
      final id = 'manual/${d.slug}';
      final seededRng = Random(_stableHash(id));

      // Study hubs tend to have better wifi/outlets than average
      final seatAvailability = _randomDouble(seededRng, min: 0.2, max: 0.9);
      final wifiSpeed = _randomDouble(seededRng, min: 0.5, max: 1.0);
      final outletCount = _randomDouble(seededRng, min: 0.4, max: 1.0);
      final weightedScore =
          (seatAvailability * 0.50) + (wifiSpeed * 0.30) + (outletCount * 0.20);
      final isOpen = (_stableHash('${id}_open').abs() % 10) >= 3;
      final distanceMeters = _haversineDistance(userLat, userLon, d.lat, d.lon);
      final imageUrl = _resolvePhoto(d.name, id, 'study_hub');

      return CafeModel(
        id: id,
        name: d.name,
        spotType: 'study_hub',
        latitude: d.lat,
        longitude: d.lon,
        address: d.address,
        seatAvailability: seatAvailability,
        wifiSpeed: wifiSpeed,
        outletCount: outletCount,
        weightedScore: weightedScore,
        imageUrl: imageUrl,
        osmTags: {
          'spot_type': 'study_hub',
          'name': d.name,
          'addr:full': d.address,
          'source': 'manual_injection',
        },
        isOpen: isOpen,
        distanceMeters: distanceMeters,
      );
    }).toList();
  }

  // ── Spot type resolution ──────────────────────────────────────────────────

  /// Determines the spot type from OSM tags and/or display name.
  ///
  /// Priority order:
  ///   1. amenity=library   → 'library'
  ///   2. office=coworking  → 'study_hub'
  ///   3. Name keywords     → 'study_hub' if matches hub/cowork/workspace
  ///   4. Default           → 'cafe'
  static String _resolveSpotType(Map<String, String> tags, String name) {
    final amenity = tags['amenity'] ?? '';
    final office = tags['office'] ?? '';
    final nameLower = name.toLowerCase();

    // 1. Explicit OSM amenity/office tags take highest priority
    if (amenity == 'library') return 'library';
    if (office == 'coworking' || office == 'co-working') return 'study_hub';

    // 2. Name-based classification for study hubs and coworking spaces
    //    Covers OSM nodes whose type is only signalled by their name,
    //    plus the three manually-injected Digos community favourites.
    if (nameLower.contains('study hub') ||
        nameLower.contains('studyhub') ||
        nameLower.contains('study space') ||
        nameLower.contains('study spot') ||
        nameLower.contains('cowork') ||
        nameLower.contains('co-work') ||
        nameLower.contains('workspace') ||
        nameLower.contains('dreamy desk') ||
        nameLower.contains('focus point') ||
        nameLower.contains('minna') ||
        nameLower.contains('hub')) {
      return 'study_hub';
    }

    // 3. Default to cafe (covers amenity=cafe and anything unrecognised)
    return 'cafe';
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Executes the Overpass query and returns the raw element list.
  static Future<List<dynamic>> _queryOverpass() async {
    final uri = Uri.parse(_overpassUrl);

    final headers = {
      'User-Agent': 'StudyspaceApp/1.0 (Flutter mobile app)',
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    late http.Response response;

    try {
      response = await http
          .post(
            uri,
            headers: headers,
            body: 'data=${Uri.encodeComponent(_query)}',
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw OsmNetworkException(
        'No internet connection or DNS failure: ${e.message}',
      );
    } on TimeoutException {
      throw OsmNetworkException(
        'Request timed out. Check your connection and try again.',
      );
    } on Exception catch (e) {
      throw OsmNetworkException('Network error: $e');
    }

    if (response.statusCode != 200) {
      throw OsmHttpException(
        'Overpass API returned HTTP ${response.statusCode}. '
        'The service may be temporarily overloaded.',
      );
    }

    late Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw OsmParseException('Failed to parse Overpass JSON: $e');
    }

    final elements = body['elements'];
    if (elements == null || elements is! List) {
      throw OsmParseException(
        'Overpass response is missing the "elements" array. '
        'The API may have changed its format.',
      );
    }

    // NOTE: An empty list is valid — fetchExternalCafes will still return
    // the manually-injected community spots even with zero OSM results.
    return elements;
  }

  /// Converts the raw OSM tags object to a [Map<String, String>].
  /// Returns an empty map when rawTags is null, preventing null-dereference
  /// crashes inside the for-loop in [fetchExternalCafes].
  static Map<String, String> _parseTags(dynamic rawTags) {
    if (rawTags is! Map) return {};
    return rawTags.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// Returns true if [name] matches any entry in [_excluded]
  /// (case-insensitive substring match).
  static bool _isExcluded(String name) {
    final lower = name.toLowerCase().trim();
    return _excluded.any((e) => lower.contains(e.toLowerCase()));
  }

  /// Extracts lat or lon from either a top-level field (nodes)
  /// or a nested `center` map (ways, requires `out center`).
  static double? _resolveCoord(Map<String, dynamic> element, String key) {
    final direct = element[key];
    if (direct is num) return direct.toDouble();

    final center = element['center'];
    if (center is Map) {
      final fromCenter = center[key];
      if (fromCenter is num) return fromCenter.toDouble();
    }
    return null;
  }

  // ── Known Digos City spot addresses ──────────────────────────────────────
  /// Curated street addresses for well-known Digos City spots.
  /// Keys are lowercase partial name matches (checked via String.contains).
  /// Used as fallback when OSM addr:* tags are missing or incomplete.
  /// Sources: Facebook pages, Google Maps, Tripadvisor, official websites.
  static const Map<String, String> _knownAddresses = {
    // ── Cafes ──────────────────────────────────────────────────────────────
    'nook': 'Mabini 3rd Street, Digos City, Davao del Sur',
    'sooyop': 'JP Laurel Avenue, Digos City, Davao del Sur',
    'blugre': 'Quezon Avenue, Digos City, Davao del Sur',
    'cafelino': 'Lim Street, Digos City, Davao del Sur',
    'denise': 'Quezon Avenue, Tres de Mayo, Digos City, Davao del Sur',
    'annipie': 'Mabini Street, Digos City, Davao del Sur',
    'coffee cat': 'JP Rizal Avenue, Digos City, Davao del Sur',
    'coffeecat': 'JP Rizal Avenue, Digos City, Davao del Sur',
    'lara mia': 'Mabini Street, Digos City, Davao del Sur',
    'demitasse': 'JP Rizal Avenue, Digos City, Davao del Sur',
    'kos cafe':
        'Donlin Commercial Bldg. 2, Roxas Extension, Digos City, Davao del Sur',
    'kopi shot': 'Rizal Avenue, Digos City, Davao del Sur',
    'coffee bean brewed': 'Mabini Street, Digos City, Davao del Sur',
    'fagioli': 'Quezon Avenue, Digos City, Davao del Sur',
    'mysa': 'Quezon Avenue, Digos City, Davao del Sur',
    'think up': 'JP Rizal Avenue, Digos City, Davao del Sur',
    'tipsy butter': 'Digos City, Davao del Sur',
    // ── Libraries ─────────────────────────────────────────────────────────
    'digos city public library':
        'JP Rizal Avenue, Poblacion, Digos City, Davao del Sur',
    'digos public library':
        'JP Rizal Avenue, Poblacion, Digos City, Davao del Sur',
    'davao del sur state college library':
        'Quezon Avenue, Digos City, Davao del Sur',
    'ddsct library': 'Quezon Avenue, Digos City, Davao del Sur',
    'umindanao library': 'Matina, Davao City, Davao del Sur',
    // ── Study Hubs & Coworking ─────────────────────────────────────────────
    'focus point': 'Quezon Avenue, Digos City, Davao del Sur',
    'dreamy desk': 'JP Laurel Street, Digos City, Davao del Sur',
    'minna': 'Rizal Avenue, Digos City, Davao del Sur',
  };

  /// Assembles a human-readable address from OSM `addr:*` tags.
  /// Falls back to [_knownAddresses] by name match, then 'Digos City'.
  static String _buildAddress(Map<String, String> tags, [String? name]) {
    final parts = <String>[];
    final housenumber = tags['addr:housenumber'];
    final street = tags['addr:street'];
    final city = tags['addr:city'];
    final suburb = tags['addr:suburb'];
    final quarter = tags['addr:quarter'];

    if (housenumber != null && street != null) {
      parts.add('$housenumber $street');
    } else if (street != null) {
      parts.add(street);
    }
    if (suburb != null) parts.add(suburb);
    if (quarter != null && quarter != suburb) parts.add(quarter);
    if (city != null) parts.add(city);

    // If OSM gave us a real address, use it.
    if (parts.isNotEmpty) return parts.join(', ');

    // Fallback: check our curated known-address map by spot name.
    if (name != null) {
      final lower = name.toLowerCase();
      for (final entry in _knownAddresses.entries) {
        if (lower.contains(entry.key)) return entry.value;
      }
    }

    return 'Digos City, Davao del Sur';
  }

  /// Returns a curated photo URL for [name] if a keyword match is found in
  /// [_namedPhotos], otherwise falls back to a type-appropriate stock photo.
  static String _resolvePhoto(String name, String id, String spotType) {
    final lower = name.toLowerCase();
    for (final entry in _namedPhotos.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    // Type-specific fallback pools
    final pool = switch (spotType) {
      'library' => _libraryStockPhotos,
      'study_hub' => _studyHubStockPhotos,
      _ => _cafeStockPhotos,
    };

    final photoIndex = _stableHash(id).abs() % pool.length;
    return pool[photoIndex];
  }

  /// Generates a stable integer hash from a string (used as a random seed).
  static int _stableHash(String input) {
    var hash = 5381;
    for (final codeUnit in input.codeUnits) {
      hash = ((hash << 5) + hash) ^ codeUnit;
    }
    return hash;
  }

  static double _randomDouble(
    Random rng, {
    double min = 0.0,
    double max = 1.0,
  }) {
    return min + rng.nextDouble() * (max - min);
  }

  /// Computes the great-circle distance in meters between two coordinates
  /// using the Haversine formula.
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;
}

// ── Exception hierarchy ───────────────────────────────────────────────────────

/// Base class for all errors thrown by [OsmCafeService].
abstract class OsmFetchException implements Exception {
  final String message;
  const OsmFetchException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when there is no internet connection, a DNS failure, or a timeout.
class OsmNetworkException extends OsmFetchException {
  const OsmNetworkException(super.message);
}

/// Thrown when the Overpass API returns a non-200 HTTP status.
class OsmHttpException extends OsmFetchException {
  const OsmHttpException(super.message);
}

/// Thrown when the response body cannot be parsed as valid JSON,
/// or the expected 'elements' key is absent.
class OsmParseException extends OsmFetchException {
  const OsmParseException(super.message);
}

/// Thrown when the query succeeds but returns zero spots.
class OsmEmptyException extends OsmFetchException {
  const OsmEmptyException(super.message);
}
