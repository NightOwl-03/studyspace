import 'package:geolocator/geolocator.dart';

/// Handles all location-related operations for the app.
/// Manages permissions, service checks, and position retrieval.
class LocationService {
  // ── Get Current Position ──────────────────────────────────────────────────
  /// Retrieves the user's current geographic position.
  ///
  /// This method:
  /// 1. Checks if location services are enabled on the device.
  /// 2. Checks if the app has location permission.
  /// 3. Requests permission if not already granted.
  /// 4. Returns the current [Position] with latitude and longitude.
  ///
  /// Returns:
  ///   - [Position] object with [latitude], [longitude], and other location data
  ///
  /// Throws:
  ///   - [Exception] if location services are disabled
  ///   - [Exception] if permission is denied or permanently denied
  static Future<Position> getCurrentPosition() async {
    try {
      // Check if location services are enabled
      final isLocationServiceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!isLocationServiceEnabled) {
        throw Exception(
          'Location services are disabled. '
          'Please enable location services in your device settings.',
        );
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      // Handle different permission states
      if (permission == LocationPermission.denied) {
        // Permission not yet requested
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception(
            'Location permissions are required to find nearby study spots. '
            'Please allow location access.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        // User has permanently denied location access
        throw Exception(
          'Location permissions are permanently denied. '
          'Please enable location access in app settings.',
        );
      }

      // If we reach here, permission is granted (either 'whileInUse' or 'always')
      // Request high-accuracy position with a timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      return position;
    } catch (e) {
      // Re-throw exceptions with context
      rethrow;
    }
  }

  // ── Get Last Known Position ──────────────────────────────────────────────
  /// Retrieves the last known position without requesting updated location.
  /// Useful for quick fallback when fresh position is not critical.
  ///
  /// Returns null if no last known position is available.
  static Future<Position?> getLastKnownPosition() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position;
    } catch (e) {
      return null;
    }
  }

  // ── Check Permission Status ──────────────────────────────────────────────
  /// Checks the current location permission status without requesting.
  ///
  /// Returns:
  ///   - [LocationPermission.granted] if permission is granted
  ///   - [LocationPermission.denied] if permission is denied
  ///   - [LocationPermission.deniedForever] if permanently denied
  static Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  // ── Open App Settings ───────────────────────────────────────────────────
  /// Opens the app's settings page where users can manually enable location.
  /// Useful when permission is permanently denied.
  static Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}
