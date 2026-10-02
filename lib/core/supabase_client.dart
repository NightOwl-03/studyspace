import 'package:supabase_flutter/supabase_flutter.dart';

/// Single access point for the Supabase client.
/// Use `db` everywhere instead of calling Supabase.instance.client directly.
///
/// Example:
///   import '../core/supabase_client.dart';
///   final rows = await db.from('study_spots').select();
final SupabaseClient db = Supabase.instance.client;
