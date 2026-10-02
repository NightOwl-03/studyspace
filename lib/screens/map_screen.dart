import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../models/study_spot.dart';
import '../models/cafe_model.dart'; // ← NEW: OSM cafe model
import '../services/study_spot_service.dart';
import '../services/osm_cafe_service.dart'; // ← NEW: OSM fetcher
import '../services/location_service.dart';

/// Full-screen map powered by flutter_map + OpenStreetMap tiles.
///
/// Data sources:
///   • [StudySpotService]  — Supabase study_spots (verified, real-time seats).
///   • [OsmCafeService]    — OpenStreetMap Overpass API (community cafes).
///
/// Both sources render as distinct marker layers so the user can
/// distinguish between verified Studyspace spots and raw OSM cafes.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ── Map controller ────────────────────────────────────────────────────────
  final MapController _mapController = MapController();

  // ── Search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSuggestions = false;
  final FocusNode _searchFocus = FocusNode();

  // ── State ─────────────────────────────────────────────────────────────────
  List<StudySpot> _spots = [];
  List<CafeModel> _osmCafes = []; // ← NEW: OSM cafes list

  bool _isLoading = true;
  bool _osmLoading = false; // ← NEW: separate OSM loading flag
  String? _osmError; // ← NEW: surfaced to UI if Overpass fails
  bool _isSatellite = false; // toggles between OSM and Esri satellite tiles

  LatLng _mapCenter = const LatLng(6.7497, 125.3550); // Digos City centre
  LatLng? _userPosition;
  StudySpot? _selectedSpot; // tapped Supabase marker
  CafeModel? _selectedCafe; // ← NEW: tapped OSM marker

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // CHANGE 1 of 4 — _init now also kicks off _loadOsmCafes in parallel.
  Future<void> _init() async {
    await _requestLocationAndCenter();
    // Run both fetches concurrently after we have the user's location.
    await Future.wait([
      _loadSpots(),
      _loadOsmCafes(), // ← uses _userPosition set by _requestLocationAndCenter
    ]);
  }

  // ── Location permission + centering ───────────────────────────────────────

  Future<void> _requestLocationAndCenter() async {
    final perm = await LocationService.checkPermission();

    if (perm == LocationPermission.deniedForever) {
      _showPermanentDenialDialog();
      return;
    }

    if (perm == LocationPermission.denied) {
      final proceed = await _showLocationRationaleDialog();
      if (!proceed) return;
    }

    try {
      final position = await LocationService.getCurrentPosition();
      if (mounted) {
        final ll = LatLng(position.latitude, position.longitude);
        setState(() {
          _userPosition = ll;
          _mapCenter = ll;
        });
        _mapController.move(ll, 15.0);
      }
    } catch (_) {
      // Permission still denied or timeout — keep default centre.
    }
  }

  Future<bool> _showLocationRationaleDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF3B82F6),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enable Location Services',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'To find the best study spots near you and show '
              'accurate distances, please enable location services.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Not Now',
              style: GoogleFonts.inter(color: Colors.black54),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Enable Location',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showPermanentDenialDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Location Access Required',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Location permission is permanently denied. '
          'Please enable it in your device settings to use this feature.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              LocationService.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Open Settings',
              style: GoogleFonts.inter(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spot loading (Supabase) ───────────────────────────────────────────────

  Future<void> _loadSpots() async {
    try {
      final spots = await StudySpotService.fetchAllSpots();
      if (mounted) {
        setState(() {
          _spots = spots;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // CHANGE 2 of 4 — NEW method: fetch OSM cafes from Overpass API.
  /// Fetches cafes from OpenStreetMap via [OsmCafeService].
  /// Runs concurrently with [_loadSpots] — has its own loading/error state.
  Future<void> _loadOsmCafes() async {
    if (!mounted) return;
    setState(() {
      _osmLoading = true;
      _osmError = null;
    });

    final userLat = _userPosition?.latitude ?? 6.7490;
    final userLon = _userPosition?.longitude ?? 125.3580;

    // ── Fetch full OSM list (manual spots always included by the service) ─────
    try {
      final cafes = await OsmCafeService.fetchExternalCafes(
        userLatitude: userLat,
        userLongitude: userLon,
      );

      if (mounted) {
        setState(() {
          _osmCafes = cafes;
          _osmLoading = false;
          _osmError = null;
        });
      }

      // ── Granular catches (FIX 2) ────────────────────────────────────────────
    } on OsmNetworkException {
      // Device has no internet or the request timed out.
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError =
              'No internet connection. Community cafes could not be loaded.';
        });
      }
    } on OsmHttpException catch (e) {
      // Overpass returned a non-200 status (e.g. 429 rate-limit, 503 overload).
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError = 'Server error: ${e.message}';
        });
      }
    } on OsmParseException {
      // Response arrived but was malformed JSON or missing 'elements'.
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError =
              'Received unexpected data from the map service. Try again later.';
        });
      }
    } on OsmEmptyException {
      // OSM returned zero results but fetchExternalCafes already injected
      // manual community spots before throwing — do NOT wipe _osmCafes here.
      // Just clear the loading flag silently.
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError = null;
        });
      }
    } catch (e) {
      // Catch-all: keep whatever cafes already loaded, just stop the spinner.
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError = 'An unexpected error occurred. Please retry.';
        });
      }
    }
  }

  // ── Marker helpers — Supabase spots ───────────────────────────────────────

  Color _markerColor(StudySpot spot) {
    final type = (spot.amenities['spot_type'] ?? spot.spotType).toLowerCase();
    if (type == 'library') return const Color(0xFF1976D2); // Blue 700
    if (type == 'study_hub' || type == 'coworking' || type.contains('hub')) {
      return const Color(0xFF512DA8); // Deep Purple 700
    }
    if (type == 'cafe' || type.contains('cafe') || type.contains('coffee')) {
      return const Color(0xFF795548); // Brown 600
    }
    // Name fallback
    final lower = spot.name.toLowerCase();
    if (lower.contains('library')) return const Color(0xFF1976D2);
    if (lower.contains('hub') ||
        lower.contains('cowork') ||
        lower.contains('workspace')) {
      return const Color(0xFF512DA8);
    }
    if (lower.contains('coffee') || lower.contains('cafe')) {
      return const Color(0xFF795548);
    }
    return const Color(0xFF6366F1);
  }

  IconData _markerIcon(StudySpot spot) {
    final type = (spot.amenities['spot_type'] ?? spot.spotType).toLowerCase();
    if (type == 'library') return Icons.menu_book;
    if (type == 'study_hub' || type == 'coworking' || type.contains('hub')) {
      return Icons.groups;
    }
    if (type == 'cafe' || type.contains('cafe')) return Icons.local_cafe;
    // Name fallback
    final lower = spot.name.toLowerCase();
    if (lower.contains('library')) return Icons.menu_book;
    if (lower.contains('hub') || lower.contains('cowork')) return Icons.groups;
    if (lower.contains('coffee') || lower.contains('cafe')) {
      return Icons.local_cafe;
    }
    return Icons.place;
  }

  Marker _buildSpotMarker(StudySpot spot) {
    final color = _markerColor(spot);
    return Marker(
      point: LatLng(spot.latitude, spot.longitude),
      width: 130,
      height: 70,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedCafe = null; // ← clear any OSM selection
          _selectedSpot = _selectedSpot?.id == spot.id ? null : spot;
        }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedSpot?.id == spot.id ? color : Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: _selectedSpot?.id == spot.id
                      ? color
                      : Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Text(
                spot.name,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _selectedSpot?.id == spot.id
                      ? Colors.white
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Icon(Icons.location_on, color: color, size: 30),
          ],
        ),
      ),
    );
  }

  // CHANGE 3 of 4 — marker builder for OSM spots: type-aware color + icon.
  /// Builds a type-coloured marker for OSM spots:
  ///   • Café        → Brown   + Icons.local_cafe
  ///   • Library     → Blue    + Icons.menu_book
  ///   • Study Hub   → Indigo  + Icons.groups
  Marker _buildCafeMarker(CafeModel cafe) {
    final Color color;
    final IconData pinIcon;
    switch (cafe.spotType) {
      case 'library':
        color = const Color(0xFF1976D2); // Blue 700
        pinIcon = Icons.menu_book;
        break;
      case 'study_hub':
        color = const Color(0xFF512DA8); // Deep Purple 700
        pinIcon = Icons.groups;
        break;
      default: // cafe
        color = const Color(0xFF795548); // Brown 600
        pinIcon = Icons.local_cafe;
    }

    final isSelected = _selectedCafe?.id == cafe.id;

    return Marker(
      point: LatLng(cafe.latitude, cafe.longitude),
      width: 120,
      height: 60,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedSpot = null; // clear any Supabase selection
          _selectedCafe = isSelected ? null : cafe;
        }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name chip — type-coloured when selected, white otherwise
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.white,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
                border: Border.all(
                  color: isSelected ? color : color.withValues(alpha: 0.40),
                  width: 1,
                ),
              ),
              child: Text(
                cafe.name,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : color,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Type-specific pin icon
            Icon(pinIcon, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  // ── User location marker ──────────────────────────────────────────────────

  Marker _buildUserMarker(LatLng pos) {
    return Marker(
      point: pos,
      width: 48,
      height: 48,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3B82F6), width: 2),
        ),
        child: const Icon(
          Icons.my_location_rounded,
          color: Color(0xFF3B82F6),
          size: 22,
        ),
      ),
    );
  }

  // ── Bottom info cards ─────────────────────────────────────────────────────

  /// Info card for a verified Supabase [StudySpot] (unchanged layout).
  Widget _buildSelectedSpotCard(StudySpot spot) {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _markerColor(spot).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _markerIcon(spot),
                  color: _markerColor(spot),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      spot.name,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spot.locationAddress,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.event_seat,
                          size: 12,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${spot.availableSeats} / ${spot.totalSeats} seats free',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.green[700],
                          ),
                        ),
                        if (spot.averageRating > 0) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            spot.averageRating.toStringAsFixed(1),
                            style: GoogleFonts.inter(fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedSpot = null),
                child: const Icon(Icons.close, size: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // CHANGE 4 of 4 — info card for an OSM [CafeModel].
  /// Type-aware info card. Shows the simulated scores, open/closed status,
  /// and a small source badge so users know it's community data.
  Widget _buildSelectedCafeCard(CafeModel cafe) {
    // ── Type-specific visuals ──────────────────────────────────────────────
    final Color accentColor;
    final IconData typeIcon;
    final Color bgTint;
    final String badgeLabel;
    switch (cafe.spotType) {
      case 'library':
        accentColor = const Color(0xFF1976D2); // Blue 700
        typeIcon = Icons.menu_book;
        bgTint = const Color(0xFFE3F2FD);
        badgeLabel = 'Library';
        break;
      case 'study_hub':
        accentColor = const Color(0xFF512DA8); // Deep Purple 700
        typeIcon = Icons.groups;
        bgTint = const Color(0xFFEDE7F6);
        badgeLabel = 'Study Hub';
        break;
      default: // cafe
        accentColor = const Color(0xFF795548); // Brown 600
        typeIcon = Icons.local_cafe;
        bgTint = const Color(0xFFFFF3E0);
        badgeLabel = 'Café';
    }

    // ── Open / closed status ───────────────────────────────────────────────
    final statusColor = cafe.isOpen ? Colors.green : Colors.redAccent;
    final statusLabel = cafe.isOpen ? 'OPEN' : 'CLOSED';

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.30),
              width: 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo thumbnail with type-tinted fallback
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  cafe.imageUrl,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 54,
                    height: 54,
                    color: bgTint,
                    child: Icon(typeIcon, color: accentColor, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name + type badge + close button
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cafe.name,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: bgTint,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cafe.address,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // Metrics row + open/closed status
                    Row(
                      children: [
                        // Open/Closed badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.circle, size: 7, color: statusColor),
                              const SizedBox(width: 3),
                              Text(
                                statusLabel,
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        _metricChip(
                          Icons.event_seat,
                          '${(cafe.seatAvailability * 100).toInt()}% free',
                          Colors.green,
                        ),
                        const SizedBox(width: 6),
                        _metricChip(
                          Icons.wifi,
                          '${(cafe.wifiSpeed * 100).toInt()}%',
                          Colors.blue,
                        ),
                        const SizedBox(width: 6),
                        _metricChip(
                          Icons.electrical_services,
                          '${(cafe.outletCount * 100).toInt()}%',
                          Colors.amber.shade700,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedCafe = null),
                child: const Icon(Icons.close, size: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small icon + label chip used inside the OSM cafe info card.
  Widget _metricChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Returns the type slug for a Supabase StudySpot (reuses existing logic)
  String _spotTypeLabel(StudySpot spot) {
    final type = (spot.amenities['spot_type'] ?? spot.spotType).toLowerCase();
    if (type == 'library') return 'library';
    if (type == 'study_hub' || type == 'coworking' || type.contains('hub')) {
      return 'study_hub';
    }
    if (type == 'cafe' || type.contains('cafe') || type.contains('coffee')) {
      return 'cafe';
    }
    final lower = spot.name.toLowerCase();
    if (lower.contains('library')) return 'library';
    if (lower.contains('hub') || lower.contains('cowork')) return 'study_hub';
    if (lower.contains('coffee') || lower.contains('cafe')) return 'cafe';
    return 'cafe';
  }

  // ── Search helpers ────────────────────────────────────────────────────────

  List<dynamic> get _allItems => [..._spots, ..._osmCafes];

  /// Items filtered by the current search query
  List<dynamic> get _searchResults {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    return _allItems
        .where((item) {
          if (item is StudySpot) {
            return item.name.toLowerCase().contains(q) ||
                (item.locationAddress ?? '').toLowerCase().contains(q);
          } else if (item is CafeModel) {
            return item.name.toLowerCase().contains(q) ||
                item.address.toLowerCase().contains(q);
          }
          return false;
        })
        .take(6)
        .toList(); // cap at 6 suggestions
  }

  /// Fly the map to a result and select its marker
  void _selectSearchResult(dynamic item) {
    _searchFocus.unfocus();
    setState(() => _showSuggestions = false);

    if (item is StudySpot) {
      final ll = LatLng(item.latitude, item.longitude);
      _mapController.move(ll, 16.0);
      setState(() {
        _selectedCafe = null;
        _selectedSpot = item;
      });
    } else if (item is CafeModel) {
      final ll = LatLng(item.latitude, item.longitude);
      _mapController.move(ll, 16.0);
      setState(() {
        _selectedSpot = null;
        _selectedCafe = item;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // Whether any bottom card is currently shown (used to push the FAB up).
  bool get _hasSelection => _selectedSpot != null || _selectedCafe != null;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Map ───────────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _mapCenter,
            initialZoom: 15.0,
            onTap: (_, __) => setState(() {
              _selectedSpot = null;
              _selectedCafe = null;
              _showSuggestions = false; // dismiss search dropdown on map tap
            }),
          ),
          children: [
            TileLayer(
              // Switch tile source based on the satellite toggle.
              // Esri World Imagery tiles use {y} before {x} in the path.
              urlTemplate: _isSatellite
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.studyspace',
            ),
            MarkerLayer(
              markers: [
                // Layer 1 — Verified Supabase study spots
                ..._spots.map(_buildSpotMarker),

                // Layer 2 — OSM community cafes (rendered below verified spots
                //           so Supabase markers stay on top when they overlap)
                ..._osmCafes.map(_buildCafeMarker), // ← NEW
                // Layer 3 — User's GPS position
                if (_userPosition != null) _buildUserMarker(_userPosition!),
              ],
            ),
          ],
        ),

        // ── Search bar + suggestions overlay ─────────────────────────────────
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Search bar
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(14),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() {
                    _searchQuery = v.trim();
                    _showSuggestions = v.trim().isNotEmpty;
                  }),
                  onTap: () {
                    if (_searchQuery.isNotEmpty) {
                      setState(() => _showSuggestions = true);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search spots, cafés, libraries...',
                    hintStyle: GoogleFonts.inter(
                      color: Colors.grey[400],
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _searchFocus.unfocus();
                              setState(() {
                                _searchQuery = '';
                                _showSuggestions = false;
                              });
                            },
                            child: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.grey,
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              // Suggestions dropdown
              if (_showSuggestions && _searchResults.isNotEmpty)
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _searchResults.map((item) {
                        final String name;
                        final String subtitle;
                        final IconData icon;
                        final Color iconColor;

                        if (item is StudySpot) {
                          name = item.name;
                          subtitle = item.locationAddress ?? '';
                          final t = _spotTypeLabel(item);
                          icon = t == 'library'
                              ? Icons.menu_book
                              : t == 'study_hub'
                              ? Icons.groups
                              : Icons.local_cafe;
                          iconColor = t == 'library'
                              ? const Color(0xFF1976D2)
                              : t == 'study_hub'
                              ? const Color(0xFF512DA8)
                              : const Color(0xFF795548);
                        } else {
                          final cafe = item as CafeModel;
                          name = cafe.name;
                          subtitle = cafe.address;
                          icon = cafe.spotType == 'library'
                              ? Icons.menu_book
                              : cafe.spotType == 'study_hub'
                              ? Icons.groups
                              : Icons.local_cafe;
                          iconColor = cafe.spotType == 'library'
                              ? const Color(0xFF1976D2)
                              : cafe.spotType == 'study_hub'
                              ? const Color(0xFF512DA8)
                              : const Color(0xFF795548);
                        }

                        return InkWell(
                          onTap: () => _selectSearchResult(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(icon, color: iconColor, size: 18),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (subtitle.isNotEmpty)
                                        Text(
                                          subtitle,
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.north_west,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // No results state
              if (_showSuggestions &&
                  _searchResults.isEmpty &&
                  _searchQuery.isNotEmpty)
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          color: Colors.grey[400],
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'No results for "$_searchQuery"',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Loading overlay (Supabase) ────────────────────────────────────────
        if (_isLoading)
          const Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                borderRadius: BorderRadius.all(Radius.circular(20)),
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading spots…'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Loading overlay (OSM) ─────────────────────────────────────────────
        // Shown only while Overpass is in-flight and below the Supabase banner.
        if (_osmLoading && !_isLoading)
          Positioned(
            top: 72,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.deepOrange.shade400,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading community spots…',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── OSM error banner ──────────────────────────────────────────────────
        // Non-blocking: Supabase spots still show; OSM ones just won't appear.
        if (_osmError != null)
          Positioned(
            top: 72,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.deepOrange.shade600,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _osmError ?? 'Community spots unavailable.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.deepOrange.shade700,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _osmError = null);
                        _loadOsmCafes(); // retry
                      },
                      child: Text(
                        'Retry',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Satellite toggle FAB ──────────────────────────────────────────────
        Positioned(
          bottom: _hasSelection ? 178 : 64, // sits 48px above the location FAB
          right: 16,
          child: FloatingActionButton.small(
            backgroundColor: _isSatellite
                ? const Color(0xFF1E293B)
                : Colors.white,
            foregroundColor: _isSatellite
                ? Colors.white
                : const Color(0xFF1E293B),
            elevation: 4,
            heroTag: 'map_satellite_fab',
            tooltip: _isSatellite ? 'Switch to Map' : 'Switch to Satellite',
            onPressed: () => setState(() => _isSatellite = !_isSatellite),
            child: Icon(
              _isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
            ),
          ),
        ),

        // ── My-location FAB ───────────────────────────────────────────────────
        Positioned(
          bottom: _hasSelection ? 130 : 16,
          right: 16,
          child: FloatingActionButton.small(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF3B82F6),
            elevation: 4,
            heroTag: 'map_location_fab',
            onPressed: () async {
              if (_userPosition != null) {
                _mapController.move(_userPosition!, 16.0);
              } else {
                await _requestLocationAndCenter();
              }
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ),

        // ── Bottom info cards ─────────────────────────────────────────────────
        // Only one card shows at a time. Supabase card takes priority because
        // _selectedSpot is cleared whenever an OSM marker is tapped.
        if (_selectedSpot != null) _buildSelectedSpotCard(_selectedSpot!),
        if (_selectedCafe != null)
          _buildSelectedCafeCard(_selectedCafe!), // ← NEW
      ],
    );
  }
}
