import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/study_spot.dart';

/// A streamlined bottom-sheet detail view for OSM (external) spots.
/// Covers all three types: Café, Library, and Study Hub / Coworking.
/// Shown when the user taps "Visit" on any external spot.
class OsmCafeDetailSheet extends StatelessWidget {
  final StudySpot spot;

  const OsmCafeDetailSheet({super.key, required this.spot});

  // ── Type resolution ─────────────────────────────────────────────────────────
  /// Reads spot_type from amenities (set by OsmCafeService) and normalises
  /// 'coworking' / 'co-working' to the unified 'study_hub' slug.
  String get _spotType {
    final raw = (spot.amenities['spot_type'] ?? '').toString().toLowerCase();
    if (raw == 'library') return 'library';
    if (raw == 'study_hub' || raw == 'coworking' || raw == 'co-working') {
      return 'study_hub';
    }
    // Name-based fallback
    final n = spot.name.toLowerCase();
    if (n.contains('library')) return 'library';
    if (n.contains('hub') || n.contains('cowork') || n.contains('workspace')) {
      return 'study_hub';
    }
    return 'cafe';
  }

  // ── Address resolution ──────────────────────────────────────────────────────
  /// Prefers the structured OSM address stored in amenities (addr:full or
  /// addr:street + addr:city), then falls back to spot.locationAddress /
  /// spot.address, and finally 'Digos City'.
  String _resolveAddress() {
    // 1. Manual-injected spots store 'addr:full'
    final full = spot.amenities['addr:full'];
    if (full is String && full.trim().isNotEmpty) return full.trim();

    // 2. OSM addr:* components
    final street = spot.amenities['addr:street'];
    final city = spot.amenities['addr:city'];
    final house = spot.amenities['addr:housenumber'];
    if (street != null && street.isNotEmpty) {
      final parts = [
        if (house != null && house.isNotEmpty) '$house $street' else street,
        if (city != null && city.isNotEmpty) city,
      ];
      return parts.join(', ');
    }

    // 3. locationAddress from the StudySpot wrapper
    final loc = spot.locationAddress;
    if (loc.isNotEmpty && loc != 'Digos City') return loc;

    // 4. Hard fallback
    return 'Digos City';
  }

  @override
  Widget build(BuildContext context) {
    final type = _spotType;
    final isOpen = spot.amenities['osm_is_open'] as bool? ?? true;
    final distanceM =
        (spot.amenities['osm_distance_meters'] as num?)?.toDouble() ??
        spot.distance;
    final distanceText = distanceM < 1000
        ? '${distanceM.toStringAsFixed(0)} m away'
        : '${(distanceM / 1000).toStringAsFixed(1)} km away';

    final wifiRaw = spot.amenities['wifi_rating'];
    final wifiScore = wifiRaw != null
        ? double.tryParse(wifiRaw.toString()) ?? 0.0
        : 0.0;

    final outletsRaw = spot.amenities['outlets'];
    final outletPct = outletsRaw != null
        ? (int.tryParse(outletsRaw.toString()) ?? 0)
        : 0;

    final statusColor = isOpen ? Colors.green : Colors.redAccent;
    final imageUrl = spot.amenities['image_url'] as String?;
    final address = _resolveAddress();

    // ── Type-specific visuals ──────────────────────────────────────────────────
    final Color accentColor;
    final Color bgTint;
    final IconData typeIcon;
    final String typeLabel; // shown in info chip + OSM notice
    switch (type) {
      case 'library':
        accentColor = const Color(0xFF1976D2); // Blue 700
        bgTint = const Color(0xFFE3F2FD);
        typeIcon = Icons.menu_book;
        typeLabel = 'Library';
        break;
      case 'study_hub':
        accentColor = const Color(0xFF512DA8); // Deep Purple 700
        bgTint = const Color(0xFFEDE7F6);
        typeIcon = Icons.groups;
        typeLabel = 'Study Hub';
        break;
      default: // cafe
        accentColor = const Color(0xFF795548); // Brown 600
        bgTint = const Color(0xFFFFF3E0);
        typeIcon = Icons.local_cafe;
        typeLabel = 'Café';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.zero,
          children: [
            // ── Drag handle ───────────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Hero image (type-tinted fallback) ─────────────────────────────
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: Image.network(
                  imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: bgTint,
                    child: Center(
                      child: Icon(typeIcon, size: 64, color: accentColor),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 160,
                color: bgTint,
                child: Center(
                  child: Icon(typeIcon, size: 64, color: accentColor),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + type badge + open badge ────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Type label (Café / Library / Study Hub)
                            Row(
                              children: [
                                Icon(typeIcon, size: 14, color: accentColor),
                                const SizedBox(width: 5),
                                Text(
                                  typeLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              spot.name,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Open/Closed badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              isOpen ? 'OPEN' : 'CLOSED',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Address + distance ────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        distanceText,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF3B82F6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // ── Stats row ─────────────────────────────────────────────
                  Row(
                    children: [
                      _StatTile(
                        icon: Icons.event_seat,
                        iconColor: Colors.green,
                        label: 'Seats Free',
                        value: '${spot.availableSeats}/${spot.totalSeats}',
                      ),
                      const SizedBox(width: 12),
                      _StatTile(
                        icon: Icons.signal_cellular_alt,
                        iconColor: Colors.blue,
                        label: 'WiFi',
                        value: '${wifiScore.toStringAsFixed(1)}/5',
                      ),
                      const SizedBox(width: 12),
                      _StatTile(
                        icon: Icons.power,
                        iconColor: Colors.orange,
                        label: 'Outlets',
                        value: '$outletPct%',
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Seat availability bar ─────────────────────────────────
                  Text(
                    'Seat Availability',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: spot.totalSeats > 0
                        ? spot.availableSeats / spot.totalSeats
                        : 0,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${spot.availableSeats} of ${spot.totalSeats} seats available',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Info chips (type-aware) ───────────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Type + city chip
                      _InfoChip(
                        icon: typeIcon,
                        label: '$typeLabel · Digos City',
                        color: accentColor,
                      ),
                      // Open/closed chip
                      _InfoChip(
                        icon: isOpen ? Icons.access_time : Icons.block,
                        label: isOpen ? 'Open now' : 'Closed',
                        color: statusColor,
                      ),
                      // WiFi chip
                      _InfoChip(icon: Icons.wifi, label: 'WiFi available'),
                      // Study Hub extras
                      if (type == 'study_hub')
                        _InfoChip(
                          icon: Icons.electrical_services,
                          label: 'Power outlets',
                        ),
                      if (type == 'library')
                        _InfoChip(
                          icon: Icons.local_library,
                          label: 'Quiet study area',
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Close button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: accentColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
