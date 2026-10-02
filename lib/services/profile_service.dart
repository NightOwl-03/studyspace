import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/user_profile.dart';
import 'auth_service.dart';

/// All Supabase interactions for the user's profile.
///
/// ROOT CAUSE FIX — "cryanjay9" showing instead of real name:
///   The app registered the user in auth.users but never inserted a matching
///   row into public.users. getProfile() returns null, and ProfileScreen falls
///   back to email.split('@').first.
///
///   Solution: [ensureProfileExists] is called from ProfileScreen.initState.
///   It checks whether a public.users row exists and, if not, creates one from
///   the auth.users metadata (display_name / email) via an UPSERT. After that,
///   [getProfile] always returns a real UserProfile.
class ProfileService {
  // ── Ensure row exists (FIXES the "cryanjay9" bug) ────────────────────────

  /// Creates a `public.users` row for the signed-in user if one does not
  /// already exist. Safe to call on every app start — the `ON CONFLICT DO
  /// NOTHING` semantics of Supabase's upsert with `ignoreDuplicates: true`
  /// make it a no-op when the row is already present.
  ///
  /// Name resolution order:
  ///   1. `user_metadata['full_name']` (set by social logins / Google OAuth)
  ///   2. `user_metadata['name']`
  ///   3. email prefix (last-resort fallback)
  static Future<void> ensureProfileExists() async {
    final user = AuthService.currentUser;
    if (user == null) return;

    // Check first so we avoid an unnecessary write on every load.
    final existing = await db
        .from('users')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();

    if (existing != null) return; // row already exists → nothing to do

    // Derive a name from auth metadata.
    final meta = user.userMetadata ?? {};
    final fullName = (meta['full_name'] ?? meta['name'] ?? '') as String;
    final nameParts = fullName.trim().split(RegExp(r'\s+'));

    final firstName = nameParts.isNotEmpty && nameParts[0].isNotEmpty
        ? nameParts[0]
        : (user.email?.split('@').first ?? 'User');
    final surname = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    await db
        .from('users')
        .upsert(
          {
            'id': user.id,
            'first_name': firstName,
            'surname': surname.isEmpty ? firstName : surname,
            'email': user.email ?? '',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'id', // update nothing if the row already exists
          ignoreDuplicates: true,
        );
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Returns the signed-in user's [UserProfile], or null if not signed in.
  ///
  /// Guaranteed to return a non-null value after [ensureProfileExists] has run.
  static Future<UserProfile?> getProfile() async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return null;

    final data = await db.from('users').select().eq('id', userId).maybeSingle();

    if (data == null) return null;
    return UserProfile.fromMap(data);
  }

  // ── Update text fields ─────────────────────────────────────────────────────

  static Future<void> updateProfile({
    required String firstName,
    String? middleName,
    required String surname,
    String? phoneNumber,
    String? bio,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in.');

    await db
        .from('users')
        .update({
          'first_name': firstName,
          'middle_name': middleName,
          'surname': surname,
          'phone_number': phoneNumber,
          'bio': bio,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  // ── Upload profile picture ─────────────────────────────────────────────────
  //
  // Stores to the "avatars" Storage bucket under a deterministic path so each
  // upload overwrites the previous file instead of accumulating orphans.
  // The resulting public URL is written back to users.profile_picture_url so
  // the Owner Web Dashboard can read it via the server-side join we added to
  // GET /api/messages/conversations.

  static Future<String> uploadProfilePicture(File imageFile) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in.');

    // Deterministic path — new upload always replaces the old avatar.
    final storagePath = '$userId/avatar.jpg';

    await db.storage
        .from('avatars')
        .upload(
          storagePath,
          imageFile,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    // Append a cache-busting timestamp so Flutter's image cache
    // doesn't serve the old photo after an update.
    final baseUrl = db.storage.from('avatars').getPublicUrl(storagePath);
    final publicUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';

    // Persist the URL — this is what the web dashboard joins on.
    await db
        .from('users')
        .update({
          'profile_picture_url': baseUrl, // store clean URL without ?t= in DB
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);

    return publicUrl; // return busted URL so Flutter re-fetches immediately
  }

  // ── Update email ───────────────────────────────────────────────────────────
  //
  // Supabase sends a confirmation link to the new address. The change only
  // takes effect after the user clicks it. We optimistically mirror the email
  // in public.users so the profile screen stays consistent.

  static Future<void> updateEmail(String newEmail) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) throw Exception('Not signed in.');

    await Supabase.instance.client.auth.updateUser(
      UserAttributes(email: newEmail),
    );

    await db
        .from('users')
        .update({
          'email': newEmail,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }
}
