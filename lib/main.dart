import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppState  —  lightweight global reactive state
//
// Business logic lives in services/.  AppState only holds UI-level
// ValueNotifiers so widgets can rebuild without passing data down the tree.
// ─────────────────────────────────────────────────────────────────────────────
class AppState {
  /// Seats currently occupied (total - available).
  static final ValueNotifier<int> seatsUsed = ValueNotifier<int>(0);

  /// Total seat capacity of the featured spot.
  static final ValueNotifier<int> totalSeats = ValueNotifier<int>(0);

  /// Whether the current user has an active check-in.
  static final ValueNotifier<bool> isCheckedIn = ValueNotifier<bool>(false);

  /// Points balance for the signed-in user.
  static final ValueNotifier<int> points = ValueNotifier<int>(0);

  /// Human-readable label of the currently reserved seat(s), e.g. "Table 1 - Seat 2".
  static final ValueNotifier<String?> reservedSeat = ValueNotifier<String?>(
    null,
  );

  /// Number of seats in the active reservation (used to release them on cancel).
  static int reservedSeatCount = 0;

  /// Active check-in ID (needed for check-out).
  static String? activeCheckInId;

  /// Active reservation ID (needed for cancellation).
  static String? activeReservationId;
}

// ─────────────────────────────────────────────────────────────────────────────
// App entry-point
// ─────────────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: "owner_web/.env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudySpace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: const Color(0xFF1E88E5),
          secondary: const Color(0xFF43A047),
          surface: Colors.white,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
      ),
      home: const SplashScreen(),
    );
  }
}
