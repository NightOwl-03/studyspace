import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/study_spot.dart';
import '../models/user_profile.dart';
import '../services/reservation_service.dart';
import '../services/study_spot_service.dart';
import '../services/profile_service.dart';
import '../services/notification_service.dart';
import '../services/location_service.dart';
import '../services/chat_service.dart';
import '../services/geofence_service.dart';
import '../services/osm_cafe_service.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'seat_selection_sheet.dart';
import 'checked_in_screen.dart';
import 'chat_list_screen.dart';
import 'osm_cafe_detail_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  String _selectedFilter = 'All';
  int _selectedIndex = 0;

  UserProfile? _profile;
  List<StudySpot> _spots = [];
  bool _isLoadingSpots = true;

  // ── Search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showSuggestions = false;

  // Location for ranked spots (default: Digos City coordinates)
  double _userLatitude = 6.7490;
  double _userLongitude = 125.3580;

  // Background notification streams
  StreamSubscription<int>? _unreadSub;
  StreamSubscription<UserNotification>? _newNotifSub;
  StreamSubscription<int>? _unreadMessagesSub;
  int _unreadCount = 0;
  int _unreadMessages = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadRankedSpots();
    _subscribeToUnread();
    _subscribeToUnreadMessages();
    _startNewNotificationListener();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    _unreadMessagesSub?.cancel();
    _newNotifSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Background notification listener ─────────────────────────────────────
  void _startNewNotificationListener() {
    _newNotifSub = NotificationService.newNotificationStream().listen((notif) {
      if (!mounted) return;
      _showNotifSnackBar(notif);
    }, onError: (_) {});
  }

  void _showNotifSnackBar(UserNotification notif) {
    IconData icon;
    Color color;
    switch (notif.type) {
      case 'new_message':
        icon = Icons.message_rounded;
        color = const Color(0xFF3B82F6);
        break;
      case 'reservation_confirmed':
        icon = Icons.check_circle_rounded;
        color = Colors.green;
        break;
      case 'reservation_cancelled':
        icon = Icons.cancel_rounded;
        color = Colors.redAccent;
        break;
      case 'reservation_pending':
        icon = Icons.hourglass_top_rounded;
        color = Colors.orange;
        break;
      case 'points_earned':
        icon = Icons.stars_rounded;
        color = Colors.amber;
        break;
      default:
        icon = Icons.notifications_rounded;
        color = const Color(0xFF6366F1);
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
          elevation: 6,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      notif.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (notif.message.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notif.message,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          action: notif.type == 'new_message'
              ? SnackBarAction(
                  label: 'View',
                  textColor: color,
                  onPressed: () {
                    setState(() => _selectedIndex = 2);
                  },
                )
              : null,
        ),
      );
  }

  // ── Data Loading ──────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    final profile = await ProfileService.getProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _loadRankedSpots() async {
    try {
      if (mounted) setState(() => _isLoadingSpots = true);

      // 1. Get user location
      try {
        final position = await LocationService.getCurrentPosition();
        _userLatitude = position.latitude;
        _userLongitude = position.longitude;
      } catch (_) {
        _userLatitude = 6.7490;
        _userLongitude = 125.3580;
      }

      // 2. Fetch from Supabase (DB)
      final dbSpots = await StudySpotService.fetchRankedSpots(
        _userLatitude,
        _userLongitude,
      );

      // 3. Fetch from OpenStreetMap (OSM)
      List<StudySpot> osmSpots = [];
      try {
        final externalCafes = await OsmCafeService.fetchExternalCafes(
          userLatitude: _userLatitude,
          userLongitude: _userLongitude,
        );

        osmSpots = externalCafes
            .map(
              (cafe) => StudySpot(
                id: cafe.id,
                ownerId: 'external_osm', // Required field
                name: cafe.name,
                locationAddress: cafe.address, // Correct field name
                latitude: cafe.latitude,
                longitude: cafe.longitude,
                city: 'Digos City', // Required field
                totalSeats: 20,
                availableSeats: (20 * cafe.seatAvailability).toInt(),
                amenities: {
                  ...cafe.osmTags,
                  // Explicit spot_type always wins over anything in osmTags
                  'spot_type': cafe.spotType,
                  'wifi_rating': (cafe.wifiSpeed * 5).toStringAsFixed(1),
                  'outlets': (cafe.outletCount * 100).toInt(),
                  'image_url': cafe.imageUrl,
                  'is_external': true,
                  'weighted_score': cafe.weightedScore,
                  'osm_is_open': cafe.isOpen,
                  'osm_distance_meters': cafe.distanceMeters,
                },
                imageUrls: [cafe.imageUrl], // Required field as a List[cite: 9]
                averageRating: 0.0, // Required field[cite: 9]
                totalReviews: 0, // Required field[cite: 9]
                status: 'active', // Required field[cite: 9]
                isVerified: false, // Required field[cite: 9]
              ),
            )
            .toList();
      } catch (e) {
        debugPrint("OSM Fetch failed: $e");
      }

      // 4. Combine and Re-sort
      final combined = [...dbSpots, ...osmSpots];

      // Manual sorting gamit ang unified scoring helper
      combined.sort((a, b) {
        final aIsExternal = a.amenities['is_external'] == true;
        final bIsExternal = b.amenities['is_external'] == true;

        // Kung ang usa external ug ang usa DB, i-una ang DB
        if (aIsExternal != bIsExternal) {
          return aIsExternal ? 1 : -1;
        }

        // Kung parehas silag source, ayha gamiton ang weighted score
        return _calculateScore(b).compareTo(_calculateScore(a));
      });

      if (mounted) {
        setState(() {
          _spots = combined;
          _isLoadingSpots = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSpots = false);
    }
  }

  // Helper function para sa scoring consistency[cite: 2]
  double _calculateScore(StudySpot spot) {
    // 50% Seats

    if (spot.amenities.containsKey('weighted_score')) {
      return (spot.amenities['weighted_score'] as num).toDouble();
    }

    double availability = spot.totalSeats > 0
        ? (spot.availableSeats / spot.totalSeats)
        : 0.0;

    // 30% WiFi (normalise 0-5 scale to 0.0-1.0)
    double wifi = 0.0;
    final rawWifi = spot.amenities['wifi_rating'] ?? spot.amenities['wifi'];
    if (rawWifi != null) {
      wifi = (double.tryParse(rawWifi.toString()) ?? 0.0) / 5.0;
    }

    // 20% Outlets (normalise 0-100 scale to 0.0-1.0)
    double outlets = 0.0;
    final rawOutlets =
        spot.amenities['outlets'] ?? spot.amenities['outlet_count'];
    if (rawOutlets != null) {
      outlets = (double.tryParse(rawOutlets.toString()) ?? 0.0) / 100.0;
    }

    return (availability * 0.50) + (wifi * 0.30) + (outlets * 0.20);
  }

  void _subscribeToUnread() {
    _unreadSub = NotificationService.unreadCountStream().listen((count) {
      if (mounted) setState(() => _unreadCount = count);
    });
  }

  void _subscribeToUnreadMessages() {
    _unreadMessagesSub = ChatService.unreadMessagesStream().listen((count) {
      if (mounted) setState(() => _unreadMessages = count);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning ☀️';
    if (hour < 17) return 'Good afternoon 🌤️';
    return 'Good evening 🌙';
  }

  String get _displayName {
    if (_profile == null) return '...';
    final parts = [
      _profile!.firstName,
      _profile!.surname,
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? 'User' : parts.join(' ');
  }

  /// Classifies a [StudySpot] into one of four categories:
  ///   'cafe' | 'library' | 'study_hub' | 'other'
  ///
  /// Resolution order:
  ///   1. Explicit spot_type / type amenity key. 'coworking' is remapped
  ///      to the unified 'study_hub' slug.
  ///   2. Name/description keyword scan as a fallback for DB spots that
  ///      pre-date the spot_type field.
  String _spotTypeForFilter(StudySpot spot) {
    final rawType = (spot.amenities['spot_type'] ?? spot.amenities['type'])
        ?.toString();

    if (rawType != null && rawType.isNotEmpty) {
      final t = rawType.toLowerCase();
      // Normalise legacy 'coworking' tag to the unified 'study_hub' slug
      if (t == 'coworking' || t == 'co-working') return 'study_hub';
      return t;
    }

    // Keyword fallback for DB spots without a spot_type tag
    final searchableText = '${spot.name} ${spot.description ?? ''}'
        .toLowerCase();

    if (searchableText.contains('library')) return 'library';

    if (searchableText.contains('study hub') ||
        searchableText.contains('studyhub') ||
        searchableText.contains('cowork') ||
        searchableText.contains('co-work') ||
        searchableText.contains('workspace') ||
        searchableText.contains('study space') ||
        searchableText.contains(' hub')) {
      return 'study_hub';
    }

    if (searchableText.contains('cafe') ||
        searchableText.contains('coffee') ||
        searchableText.contains('espresso') ||
        searchableText.contains('kaffee') ||
        searchableText.contains('kape')) {
      return 'cafe';
    }

    return 'other';
  }

  // ── Search suggestions ────────────────────────────────────────────────────

  List<StudySpot> get _searchSuggestions {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    return _spots
        .where(
          (s) =>
              s.name.toLowerCase().contains(q) ||
              (s.locationAddress ?? '').toLowerCase().contains(q) ||
              (s.description ?? '').toLowerCase().contains(q),
        )
        .take(6)
        .toList();
  }

  void _onSuggestionTapped(StudySpot spot) {
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = spot.name;
      _searchController.text = spot.name;
      _showSuggestions = false;
    });
  }

  Widget _buildSearchSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _searchSuggestions.asMap().entries.map((entry) {
            final i = entry.key;
            final spot = entry.value;
            final type = _spotTypeForFilter(spot);
            final icon = type == 'library'
                ? Icons.menu_book
                : type == 'study_hub'
                ? Icons.groups
                : Icons.local_cafe;
            final iconColor = type == 'library'
                ? const Color(0xFF1976D2)
                : type == 'study_hub'
                ? const Color(0xFF512DA8)
                : const Color(0xFF795548);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (i > 0) Divider(height: 1, color: Colors.grey.shade100),
                InkWell(
                  onTap: () => _onSuggestionTapped(spot),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: iconColor, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                spot.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if ((spot.locationAddress ?? '').isNotEmpty)
                                Text(
                                  spot.locationAddress,
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
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Filtered spots ────────────────────────────────────────────────────────

  List<StudySpot> get _filteredSpots {
    List<StudySpot> result = _spots;

    // Apply category filter first
    if (_selectedFilter != 'All') {
      final typeMap = {
        'Cafés': 'cafe',
        'Libraries': 'library',
        'Study Hubs': 'study_hub',
      };
      final type = typeMap[_selectedFilter];
      if (type != null) {
        result = result.where((s) => _spotTypeForFilter(s) == type).toList();
      }
    }

    // Then apply search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        return s.name.toLowerCase().contains(q) ||
            (s.locationAddress ?? '').toLowerCase().contains(q) ||
            (s.description ?? '').toLowerCase().contains(q);
      }).toList();
    }

    return result;
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed Top Header — hidden on Map tab (map has its own search bar)
            if (_selectedIndex != 1)
              Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedIndex == 0) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting(),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                _displayName,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const NotificationsScreen(),
                                      ),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.notifications_outlined,
                                        color: Color(0xFF195F9C),
                                      ),
                                    ),
                                  ),
                                  if (_unreadCount > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          _unreadCount > 9
                                              ? '9+'
                                              : '$_unreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _selectedIndex = 3),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  child: const Icon(
                                    Icons.person,
                                    color: Color(0xFF195F9C),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_selectedIndex == 0) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: (value) => setState(() {
                            _searchQuery = value.trim();
                            _showSuggestions = value.trim().isNotEmpty;
                          }),
                          onTap: () {
                            if (_searchQuery.isNotEmpty) {
                              setState(() => _showSuggestions = true);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Search cafés, libraries...',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.grey[400],
                            ),
                            border: InputBorder.none,
                            icon: const Icon(
                              Icons.search,
                              color: Color(0xFF3B82F6),
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _searchController.clear();
                                      _searchFocusNode.unfocus();
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
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Suggestions dropdown
            if (_selectedIndex != 1 &&
                _showSuggestions &&
                _searchSuggestions.isNotEmpty)
              _buildSearchSuggestions(),

            // Body
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildHomeFeed(),
                  const MapScreen(),
                  const ChatListScreen(),
                  const ProfileScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF3B82F6),
        unselectedItemColor: Colors.grey,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline_rounded),
                if (_unreadMessages > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _unreadMessages > 9 ? '9+' : '$_unreadMessages',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ── Home Feed ─────────────────────────────────────────────────────────────
  Widget _buildHomeFeed() {
    final filtered = _filteredSpots;
    final featured = filtered.take(2).toList();
    final rest = filtered.skip(2).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingSpots)
            _buildHeroSkeleton()
          else if (_spots.isNotEmpty)
            _buildHeroCard(_spots.first)
          else
            _buildEmptyHero(),

          const SizedBox(height: 24),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', null),
                const SizedBox(width: 8),
                _buildFilterChip('Cafés', Icons.local_cafe),
                const SizedBox(width: 8),
                _buildFilterChip('Libraries', Icons.menu_book),
                const SizedBox(width: 8),
                _buildFilterChip('Study Hubs', Icons.groups),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 4),
                  Text(
                    'Featured Spots',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                'See all',
                style: GoogleFonts.inter(
                  color: const Color(0xFF195F9C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoadingSpots)
            const Center(child: CircularProgressIndicator())
          else if (featured.isEmpty && _searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No spots found for "$_searchQuery"',
                      style: GoogleFonts.inter(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (featured.isEmpty)
            Center(
              child: Text(
                'No spots available right now.',
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < featured.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    _buildFeaturedCard(featured[i]),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 24),

          if (!_isLoadingSpots)
            for (final spot in rest) ...[
              _buildSpotCard(spot),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }

  // ── Hero Card ─────────────────────────────────────────────────────────────
  Widget _buildHeroCard(StudySpot spot) {
    final freeSeats = spot.availableSeats;
    final totalSeats = spot.totalSeats;
    final occupancyRatio = totalSeats > 0
        ? (totalSeats - freeSeats) / totalSeats
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧠 ', style: TextStyle(fontSize: 12)),
              Text(
                'BEST SPOT FOR YOU RIGHT NOW',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            spot.name,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniTag(Icons.circle, 'Available', Colors.greenAccent),
              const SizedBox(width: 8),
              if (spot.wifiRating != null)
                _buildMiniTag(
                  Icons.wifi,
                  '${spot.wifiRating!.toStringAsFixed(1)}/5 WiFi',
                  Colors.white70,
                ),
              const SizedBox(width: 8),
              _buildMiniTag(
                Icons.star,
                '${spot.averageRating.toStringAsFixed(1)} rated',
                Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Details',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$freeSeats/$totalSeats seats available',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
              ),
              Text(
                '${((1 - occupancyRatio) * 100).toInt()}% free',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: occupancyRatio.clamp(0.0, 1.0),
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (spot.minimumSpend != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₱${spot.minimumSpend!.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'min. order',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  final selectedResult =
                      await showModalBottomSheet<SeatSelectionResult>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) =>
                            SeatSelectionSheet(studySpotId: spot.id),
                      );
                  if (selectedResult != null && mounted) {
                    await _reserveSeats(spot, selectedResult);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.event_seat, size: 18),
                label: Text(
                  'Reserve Seat',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSkeleton() {
    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildEmptyHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            'No study spots found.',
            style: GoogleFonts.inter(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ── Featured Card ─────────────────────────────────────────────────────────
  Widget _buildFeaturedCard(StudySpot spot) {
    // For OSM spots use stored isOpen flag; for DB spots use spot.isOpen
    final isExternal = spot.amenities['is_external'] == true;
    final isOpenStatus = isExternal
        ? (spot.amenities['osm_is_open'] as bool? ?? true)
        : spot.isOpen;

    final isAvailable = spot.availableSeats > 0;
    final statusColor = isOpenStatus
        ? (isAvailable ? Colors.green : Colors.orange)
        : Colors.redAccent;
    final statusLabel = isOpenStatus
        ? (isAvailable
              ? 'OPEN · ${spot.availableSeats} SEATS'
              : 'LIMITED · ${spot.availableSeats} LEFT')
        : 'CLOSED';

    // ── Type-specific visuals ─────────────────────────────────────────────
    final spotType = _spotTypeForFilter(spot);
    final bgColorMap = {
      'cafe': const Color(0xFFFFF3E0), // warm amber tint  — Brown family
      'library': const Color(0xFFE3F2FD), // cool sky tint    — Blue family
      'study_hub': const Color(0xFFEDE7F6), // soft lavender    — Deep Purple
    };
    final iconMap = {
      'cafe': Icons.local_cafe,
      'library': Icons.menu_book,
      'study_hub': Icons.groups,
    };
    final accentColorMap = {
      'cafe': const Color(0xFF795548), // Brown 600
      'library': const Color(0xFF1976D2), // Blue 700
      'study_hub': const Color(0xFF512DA8), // Deep Purple 700
    };
    final icon = iconMap[spotType] ?? Icons.place;
    final accentColor = accentColorMap[spotType] ?? const Color(0xFF3B82F6);
    final bgColor = bgColorMap[spotType] ?? const Color(0xFFEEEEEE);
    final seatsUsed = spot.totalSeats - spot.availableSeats;

    // Distance display
    final distanceM = isExternal
        ? (spot.amenities['osm_distance_meters'] as num?)?.toDouble() ??
              spot.distance
        : spot.distance;
    final distanceKm = distanceM / 1000;
    final distanceText = distanceM < 1000
        ? '${distanceM.toStringAsFixed(0)}m'
        : '${distanceKm.toStringAsFixed(1)}km';

    return GestureDetector(
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Featured card image area ─────────────────────────────────
            SizedBox(
              height: 110,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo or fallback
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Builder(
                      builder: (_) {
                        final rawUrl = spot.amenities['image_url'];
                        final imageUrl = rawUrl is String && rawUrl.isNotEmpty
                            ? rawUrl
                            : (spot.imageUrls.isNotEmpty
                                  ? spot.imageUrls.first
                                  : null);
                        if (imageUrl != null) {
                          return Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: bgColor,
                              child: Center(
                                child: Icon(
                                  icon,
                                  size: 40,
                                  color: accentColor.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                ? child
                                : Container(
                                    color: bgColor,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: accentColor,
                                      ),
                                    ),
                                  ),
                          );
                        }
                        return Container(
                          color: bgColor,
                          child: Center(
                            child: Icon(
                              icon,
                              size: 40,
                              color: accentColor.withValues(alpha: 0.4),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.4),
                        ],
                      ),
                    ),
                  ),
                  // Status badge (top-left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Rating + Distance badges (bottom-right)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                spot.averageRating.toStringAsFixed(1),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 11,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                distanceText,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.name,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          spot.address,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Rating + Distance row
                  Row(
                    children: [
                      const Icon(Icons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        spot.averageRating.toStringAsFixed(1),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        distanceText,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: spot.totalSeats > 0
                        ? seatsUsed / spot.totalSeats
                        : 0,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${spot.availableSeats} of ${spot.totalSeats} seats available',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Visit + Reserve buttons ────────────────────────────
                  Row(
                    children: [
                      // Visit button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (isExternal) {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => OsmCafeDetailSheet(spot: spot),
                              );
                            } else {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => OsmCafeDetailSheet(spot: spot),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3B82F6),
                            side: const BorderSide(color: Color(0xFF3B82F6)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.store, size: 15),
                          label: Text(
                            'Visit',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Reserve button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isOpenStatus
                              ? () async {
                                  final selectedResult =
                                      await showModalBottomSheet<
                                        SeatSelectionResult
                                      >(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => SeatSelectionSheet(
                                          studySpotId: spot.id,
                                        ),
                                      );
                                  if (selectedResult != null && mounted) {
                                    await _reserveSeats(spot, selectedResult);
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            disabledBackgroundColor: Colors.grey[300],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.event_seat, size: 15),
                          label: Text(
                            isOpenStatus ? 'Reserve' : 'Closed',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Spot List Card ────────────────────────────────────────────────────────
  Widget _buildSpotCard(StudySpot spot) {
    final spotType = _spotTypeForFilter(spot);

    final iconMap = {
      'cafe': Icons.local_cafe,
      'library': Icons.menu_book,
      'study_hub': Icons.groups,
    };
    final accentColorMap = {
      'cafe': const Color(0xFF795548), // Brown 600
      'library': const Color(0xFF1976D2), // Blue 700
      'study_hub': const Color(0xFF512DA8), // Deep Purple 700
    };
    final bgColorMap = {
      'cafe': const Color(0xFFFFF3E0),
      'library': const Color(0xFFE3F2FD),
      'study_hub': const Color(0xFFEDE7F6),
    };

    final icon = iconMap[spotType] ?? Icons.place;
    final accentColor = accentColorMap[spotType] ?? const Color(0xFF3B82F6);
    final bgColor = bgColorMap[spotType] ?? const Color(0xFFEEEEEE);

    final isExternal = spot.amenities['is_external'] == true;
    final isOpenStatus = isExternal
        ? (spot.amenities['osm_is_open'] as bool? ?? true)
        : spot.isOpen;

    final rawDist = isExternal
        ? (spot.amenities['osm_distance_meters'] as num?)?.toDouble() ??
              spot.distance
        : spot.distance;
    final distanceKm = rawDist / 1000;
    final distanceText = rawDist < 1000
        ? '${rawDist.toStringAsFixed(0)}m'
        : '${distanceKm.toStringAsFixed(1)}km';

    final statusColor = isOpenStatus ? Colors.green : Colors.redAccent;
    final statusLabel = isOpenStatus ? 'OPEN' : 'CLOSED';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Spot card image area ───────────────────────────────────────
          SizedBox(
            height: 160,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Photo or dark fallback
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Builder(
                    builder: (_) {
                      final rawUrl = spot.amenities['image_url'];
                      final imageUrl = rawUrl is String && rawUrl.isNotEmpty
                          ? rawUrl
                          : (spot.imageUrls.isNotEmpty
                                ? spot.imageUrls.first
                                : null);
                      if (imageUrl != null) {
                        return Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: bgColor,
                            child: Center(
                              child: Icon(
                                icon,
                                size: 64,
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                              ? child
                              : Container(
                                  color: bgColor,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                        );
                      }
                      return Container(
                        color: bgColor,
                        child: Center(
                          child: Icon(
                            icon,
                            size: 64,
                            color: accentColor.withValues(alpha: 0.35),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Gradient overlay
                Container(
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xAA000000)],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              spot.averageRating.toStringAsFixed(1),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              distanceText,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        spot.address,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.signal_cellular_alt,
                      size: 14,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      spot.wifiRating != null
                          ? '${spot.wifiRating!.toStringAsFixed(1)}/5 WiFi'
                          : 'No WiFi info',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.event_seat, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '${spot.availableSeats} seats free',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Progress bar
                LinearProgressIndicator(
                  value: spot.totalSeats > 0
                      ? (spot.totalSeats - spot.availableSeats) /
                            spot.totalSeats
                      : 0,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 5),
                Text(
                  '${spot.availableSeats} of ${spot.totalSeats} seats available',
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                // Buttons — Visit + Reserve (external) or Reserve only (DB)
                if (isExternal)
                  Row(
                    children: [
                      // Visit button — opens streamlined detail sheet
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => OsmCafeDetailSheet(spot: spot),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3B82F6),
                            side: const BorderSide(color: Color(0xFF3B82F6)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.store, size: 18),
                          label: Text(
                            'Visit',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Reserve button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isOpenStatus
                              ? () async {
                                  final selectedResult =
                                      await showModalBottomSheet<
                                        SeatSelectionResult
                                      >(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => SeatSelectionSheet(
                                          studySpotId: spot.id,
                                        ),
                                      );
                                  if (selectedResult != null && mounted) {
                                    await _reserveSeats(spot, selectedResult);
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            disabledBackgroundColor: Colors.grey[300],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.event_seat, size: 18),
                          label: Text(
                            isOpenStatus ? 'Reserve' : 'Closed',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  // DB spot — full-width Reserve only
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isOpenStatus
                          ? () async {
                              final selectedResult =
                                  await showModalBottomSheet<
                                    SeatSelectionResult
                                  >(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => SeatSelectionSheet(
                                      studySpotId: spot.id,
                                    ),
                                  );
                              if (selectedResult != null && mounted) {
                                await _reserveSeats(spot, selectedResult);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        disabledBackgroundColor: Colors.grey[300],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.event_seat, size: 18),
                      label: Text(
                        isOpenStatus ? 'Reserve' : 'Closed',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reservation + Geofence ────────────────────────────────────────────────

  // ignore: unused_element
  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _reserveSeats(
    StudySpot spot,
    SeatSelectionResult selection,
  ) async {
    if (!mounted) return;

    // ── 1. Ban check ───────────────────────────────────────────────────────
    final userId = _profile?.id;
    if (userId != null) {
      final banMessage = await GeofenceService.checkBanStatus(userId);
      if (banMessage != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.block_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    banMessage,
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
    }

    // ── 2. Validate that the user actually picked times ────────────────────
    final timeRegex = RegExp(r'^\d{2}:\d{2}$');
    if (!timeRegex.hasMatch(selection.startTime) ||
        !timeRegex.hasMatch(selection.endTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Please select a start time and end time before reserving.',
                  style: GoogleFonts.inter(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // ── 3. Show loading ────────────────────────────────────────────────────
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final today = DateTime.now();

      final startParts = selection.startTime.split(':');
      final startDateTime = DateTime(
        today.year,
        today.month,
        today.day,
        int.parse(startParts[0]),
        int.parse(startParts[1]),
      );

      final reservation = await ReservationService.createReservation(
        studySpotId: spot.id,
        tableId: selection.tableId,
        seatIds: selection.seatIds,
        reservationDate: today,
        startTime: selection.startTime,
        endTime: selection.endTime,
      );

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      // ── 3. Build ActiveReservation for GeofenceService ─────────────────
      final activeRes = ActiveReservation(
        id: reservation.id,
        userId: reservation.userId,
        studySpotId: spot.id,
        startDateTime: startDateTime, // ← user-chosen time, not DateTime.now()
        seatIds: selection.seatIds,
      );

      // ── 4. Start geofence monitoring ───────────────────────────────────
      final geofenceService = GeofenceService();
      geofenceService.startMonitoring(activeRes, spot);

      // ── 5. Navigate to CheckedInScreen, passing the service ────────────
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckedInScreen(
            spotName: spot.name,
            tableLabel: selection.tableLabel,
            seatLabels: selection.seatLabels,
            bookingReference: reservation.bookingReference ?? '',
            reservationId: reservation.id,
            startTime: selection.startTime,
            endTime: selection.endTime,
            geofenceService: geofenceService,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reservation failed: $e',
            style: GoogleFonts.inter(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ── Small Helpers ─────────────────────────────────────────────────────────
  Widget _buildMiniTag(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData? icon) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.black54,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
