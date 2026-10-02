import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

/// Handles all authentication operations.
/// Screens should call these methods — never call db.auth directly from UI.
class AuthService {
  // ── Sign In ──────────────────────────────────────────────────────────────
  /// Signs the user in with email + password via Supabase Auth.
  /// Updates last_login in public.users on success.
  /// Throws [AuthException] on bad credentials.
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await db.auth.signInWithPassword(
      email: email,
      password: password,
    );

    // Update last_login in public.users (non-fatal if it fails)
    try {
      await db
          .from('users')
          .update({'last_login': DateTime.now().toIso8601String()})
          .eq('id', response.user!.id);
    } catch (_) {}

    return response;
  }

  // ── Register ─────────────────────────────────────────────────────────────
  /// Creates a new Supabase Auth user AND inserts a row in public.users.
  ///
  /// Supabase Auth handles the auth.users row.
  /// We insert public.users manually so we can store first_name, surname, etc.
  ///
  /// Throws [AuthException] if the email is already taken.
  static Future<void> register({
    required String firstName,
    String? middleName,
    required String surname,
    required String email,
    required String password,
    String? phoneNumber,
  }) async {
    // 1. Create the auth user
    final response = await db.auth.signUp(email: email, password: password);

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Registration failed: no user ID returned.');
    }

    // 2. Insert the public profile row linked by FK (users.id → auth.users.id)
    await db.from('users').insert({
      'id': userId,
      'first_name': firstName,
      'middle_name': middleName,
      'surname': surname,
      'email': email,
      'phone_number': phoneNumber,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Change Password ───────────────────────────────────────────────────────
  /// Updates the current user's password via Supabase Auth.
  /// The user must already be signed in (valid session required).
  ///
  /// Note: Supabase Auth does not verify the "current password" on update —
  /// it trusts the active session.  If you need to verify the old password
  /// first, call signIn() with the old password before calling this.
  static Future<void> changePassword({required String newPassword}) async {
    await db.auth.updateUser(UserAttributes(password: newPassword));
  }

  // ── Sign Out ─────────────────────────────────────────────────────────────
  /// Signs the current user out and invalidates the local session.
  static Future<void> signOut() async {
    await db.auth.signOut();
  }

  // ── Current User ──────────────────────────────────────────────────────────
  /// Returns the currently signed-in Supabase Auth user, or null.
  static User? get currentUser => db.auth.currentUser;

  /// True if there is an active session.
  static bool get isSignedIn => db.auth.currentSession != null;
}
