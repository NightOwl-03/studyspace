import 'dart:async';
import '../core/supabase_client.dart';
import '../models/study_spot.dart';

/// Handles all read operations on public.study_spots.
///
/// ROOT CAUSE FIX — "Green Coffee missing":
///   The PostgreSQL RPC `get_ranked_study_spots` uses arithmetic on
///   amenities columns (wifi_rating, outlets). Any NULL in those columns
///   causes Postgres to return NULL for the whole score expression.
///   Postgres then either drops the row from results or returns it with
///   a null weighted_score — either way, the spot disappears.
///
///   Solution: `fetchRankedSpots` now calls `fetchAllSpots` (a plain SELECT *)
///   which never filters rows, then applies the weighted scoring formula
///   client-side with explicit null → 0 coercion. Every spot always appears;
///   spots with no amenity data just get a score of 0 for that category.
///
/// Weighted scoring formula:
///   availability_pct = (available_seats / total_seats) * 100   → default 0
///   wifi_score       = amenities['wifi_rating'] / 5 * 100      → default 0
///   outlet_score     = amenities['outlets'] (0–100 scale)      → default 0
///
///   final_score = (availability_pct * 0.50)
///               + (wifi_score       * 0.30)
///               + (outlet_score     * 0.20)
class StudySpotService {
  // ── Fetch All Active Spots ────────────────────────────────────────────────

  /// Returns all spots with status = 'active', unordered (sorting is done
  /// client-side in [fetchRankedSpots]).
  static Future<List<StudySpot>> fetchAllSpots() async {
    final data = await db.from('study_spots').select().eq('status', 'active');

    return (data as List)
        .map((row) => StudySpot.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  // ── Fetch Ranked Spots (null-safe, client-side scoring) ───────────────────

  /// Returns all active spots ranked by a weighted score.
  ///
  /// Tries the Supabase RPC first for server-side distance calculation.
  /// If the RPC fails (e.g. NULL score bug) or returns an empty list,
  /// falls back to a plain SELECT and applies scoring client-side.
  ///
  /// NULL values in any amenity field are treated as 0 — spots are NEVER
  /// filtered out due to missing data.
  static Future<List<StudySpot>> fetchRankedSpots(
    double latitude,
    double longitude,
  ) async {
    // ── 1. Try RPC (gives server-side distance_meters) ────────────────────
    try {
      final data =
          await db.rpc(
                'get_ranked_study_spots',
                params: {'user_lat': latitude, 'user_lon': longitude},
              )
              as List<dynamic>;

      if (data.isNotEmpty) {
        final spots = data
            .map((row) => StudySpot.fromMap(row as Map<String, dynamic>))
            .toList();

        // Apply client-side scoring even to RPC results to guard against
        // any spot that the RPC returned with a null weighted_score.
        return _applyClientScoring(spots);
      }
    } catch (_) {
      // RPC not available or threw — fall through to client-side path.
    }

    // ── 2. Fallback: plain SELECT + client-side scoring ────────────────────
    final spots = await fetchAllSpots();
    return _applyClientScoring(spots);
  }

  // ── Weighted Scoring (client-side, null-safe) ─────────────────────────────

  /// Computes the weighted score for each spot, sorts descending, and
  /// returns the list. Spots with all-null amenity data score 0 but are
  /// NEVER excluded.
  static List<StudySpot> _applyClientScoring(List<StudySpot> spots) {
    // Build (spot, score) pairs so we can sort without mutating the model.
    final scored = spots.map((spot) {
      // ── Availability (50%) ──────────────────────────────────────────────
      // Percentage of seats still available: 100 = all free, 0 = all taken.
      double availabilityPct = 0.0;
      if (spot.totalSeats > 0) {
        availabilityPct =
            (spot.availableSeats / spot.totalSeats).clamp(0.0, 1.0) * 100.0;
      }

      // ── Wi-Fi score (30%) ───────────────────────────────────────────────
      // wifi_rating stored on a 0–5 scale in amenities → normalise to 0–100.
      // Accepts null silently → 0.
      double wifiScore = 0.0;
      final rawWifi = spot.amenities['wifi_rating'] ?? spot.amenities['wifi'];
      if (rawWifi != null) {
        final wifiRating = rawWifi is num
            ? rawWifi.toDouble()
            : double.tryParse('$rawWifi');
        if (wifiRating != null && wifiRating > 0) {
          wifiScore = (wifiRating / 5.0).clamp(0.0, 1.0) * 100.0;
        }
      }

      // ── Outlet score (20%) ──────────────────────────────────────────────
      // outlets stored as a 0–100 numeric value in amenities.
      // Accepts null silently → 0.
      double outletScore = 0.0;
      final rawOutlets =
          spot.amenities['outlets'] ?? spot.amenities['outlet_count'];
      if (rawOutlets != null) {
        final outlets = rawOutlets is num
            ? rawOutlets.toDouble()
            : double.tryParse('$rawOutlets');
        if (outlets != null) {
          // Normalise to 0–100 (assume max of 10 physical outlets → full score).
          outletScore = (outlets / 10.0).clamp(0.0, 1.0) * 100.0;
        }
      }

      // ── Final weighted score ────────────────────────────────────────────
      final finalScore =
          (availabilityPct * 0.50) + (wifiScore * 0.30) + (outletScore * 0.20);

      return _ScoredSpot(spot: spot, score: finalScore);
    }).toList();

    // Sort highest score first.
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.spot).toList();
  }

  // ── Fetch Single Spot ─────────────────────────────────────────────────────

  static Future<StudySpot?> fetchSpotById(String spotId) async {
    final data = await db
        .from('study_spots')
        .select()
        .eq('id', spotId)
        .maybeSingle();

    if (data == null) return null;
    return StudySpot.fromMap(data);
  }

  // ── Real-time Stream for One Spot ─────────────────────────────────────────

  static Stream<StudySpot?> spotStream(String spotId) {
    return db
        .from('study_spots')
        .stream(primaryKey: ['id'])
        .eq('id', spotId)
        .map((rows) => rows.isNotEmpty ? StudySpot.fromMap(rows.first) : null);
  }

  // ── Real-time Stream for All Active Spots ─────────────────────────────────

  static Stream<List<StudySpot>> allSpotsStream() {
    return db
        .from('study_spots')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .map((rows) => rows.map((row) => StudySpot.fromMap(row)).toList());
  }
}

/// Internal helper pairing a [StudySpot] with its computed weighted score.
class _ScoredSpot {
  final StudySpot spot;
  final double score;
  const _ScoredSpot({required this.spot, required this.score});
}
