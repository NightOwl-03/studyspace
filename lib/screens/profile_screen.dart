import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../models/user_profile.dart';
import 'splash_screen.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'reservations_history_screen.dart';
import 'help_support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initProfile();
  }

  /// Guarantees a public.users row exists before fetching.
  ///
  /// This is the one-line fix for the "cryanjay9" bug:
  ///   If the user signed up via Supabase Auth but the trigger / sign-up flow
  ///   never inserted a public.users row, getProfile() returned null and the
  ///   screen fell back to email.split('@').first.
  ///   ensureProfileExists() upserts a minimal row from auth metadata so
  ///   getProfile() always finds something.
  Future<void> _initProfile() async {
    try {
      await ProfileService.ensureProfileExists(); // ← THE FIX
      await _loadProfile();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await AuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Future<void> _openEditProfile() async {
    final didChange = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    // Reload so the updated name / photo appears immediately.
    if (didChange == true) _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _isLoading
          ? const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),

                // ── Profile picture ──────────────────────────────────────────
                CircleAvatar(
                  radius: 50,
                  backgroundColor: primaryColor.withValues(alpha: 0.12),
                  backgroundImage: _profile?.profilePictureUrl != null
                      ? NetworkImage(_profile!.profilePictureUrl!)
                      : null,
                  child: _profile?.profilePictureUrl == null
                      ? Icon(Icons.person, size: 50, color: primaryColor)
                      : null,
                ),
                const SizedBox(height: 16),

                // ── Real name from public.users ───────────────────────────────
                // BEFORE: fell back to email.split('@').first → "cryanjay9"
                // AFTER:  _profile.fullName → "Ryan Cabano" (or similar)
                Text(
                  _profile?.fullName ?? 'User',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  _profile?.email ??
                      AuthService.currentUser?.email ??
                      'email@example.com',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (_profile?.bio != null && _profile!.bio!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _profile!.bio!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // ── Options ──────────────────────────────────────────────────
                _buildOptionTile(
                  context,
                  icon: Icons.edit,
                  title: 'Edit Profile Details',
                  onTap: _openEditProfile,
                ),
                _buildOptionTile(
                  context,
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                _buildOptionTile(
                  context,
                  icon: Icons.event_note_rounded,
                  title: 'My Reservations',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ReservationsHistoryScreen(),
                    ),
                  ),
                ),
                _buildOptionTile(
                  context,
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HelpSupportScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Logout ───────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      'Log Out',
                      style: GoogleFonts.inter(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
