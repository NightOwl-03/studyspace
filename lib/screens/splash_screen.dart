import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'intro_screen.dart';
import 'home_screen.dart';

/// Shows the logo for ~2 seconds, then:
/// - If a valid Supabase session exists → go directly to HomeScreen.
/// - Otherwise → go to IntroScreen (onboarding / login flow).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Wait for the logo to show
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    // Check for an existing Supabase session
    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            session != null ? const HomeScreen() : const IntroScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/logo.png', width: 200),
            const SizedBox(height: 16),
            Text(
              'StudySpace',
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF195F9C),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find Your Perfect Spot',
              style: GoogleFonts.inter(
                fontSize: 16,
                color: const Color(0xFF72BF44),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
