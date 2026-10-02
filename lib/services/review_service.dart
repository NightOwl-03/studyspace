import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import 'auth_service.dart';

/// Handles submitting reviews directly to Supabase — no Node.js server needed.
class ReviewService {
  /// Submits a review for a completed reservation.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> submitReview({
    required String studySpotId,
    required int rating,
    String? comment,
  }) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return 'You must be logged in to submit a review.';

    try {
      // Check for duplicate review
      final existing = await db
          .from('reviews')
          .select('id')
          .eq('user_id', userId)
          .eq('study_spot_id', studySpotId)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        return 'You have already reviewed this spot.';
      }

      // Insert the review
      final result = await db
          .from('reviews')
          .insert({
            'user_id': userId,
            'study_spot_id': studySpotId,
            'rating': rating,
            'comment': (comment?.trim().isEmpty ?? true)
                ? null
                : comment!.trim(),
            'verified_review': true,
            'review_date': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final reviewId = result['id'] as String;

      // Recalculate average_rating + total_reviews on study_spots
      final allReviews = await db
          .from('reviews')
          .select('rating')
          .eq('study_spot_id', studySpotId);

      if ((allReviews as List).isNotEmpty) {
        final avg =
            allReviews.fold<double>(
              0,
              (sum, r) => sum + (r['rating'] as num).toDouble(),
            ) /
            allReviews.length;

        await db
            .from('study_spots')
            .update({
              'average_rating': double.parse(avg.toStringAsFixed(1)),
              'total_reviews': allReviews.length,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', studySpotId);
      }

      // Notify the owner — wrapped in try/catch so an RLS error
      // on owner_notifications never blocks a successful review submission.
      try {
        final spotData = await db
            .from('study_spots')
            .select('owner_id, name')
            .eq('id', studySpotId)
            .single();

        final ownerId = spotData['owner_id'] as String?;
        final spotName = spotData['name'] as String? ?? 'your spot';

        if (ownerId != null) {
          final stars = '⭐' * rating;
          final preview = (comment?.trim().isNotEmpty ?? false)
              ? ': "${comment!.trim().substring(0, comment.trim().length.clamp(0, 80))}"'
              : '.';
          await db.from('owner_notifications').insert({
            'owner_id': ownerId,
            'notification_type': 'review_posted',
            'title': 'New Review Received',
            'message': 'A customer rated $spotName $stars ($rating/5)$preview',
            'related_resource_id': reviewId,
            'is_read': false,
          });
        }
      } catch (_) {
        // Silently ignore — review was already saved successfully.
        // Fix: add RLS INSERT policy on owner_notifications in Supabase.
      }

      return null; // success
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Returns true if the user has already reviewed this study spot.
  static Future<bool> hasReviewed(String studySpotId) async {
    final userId = AuthService.currentUser?.id;
    if (userId == null) return false;

    final data = await db
        .from('reviews')
        .select('id')
        .eq('user_id', userId)
        .eq('study_spot_id', studySpotId)
        .limit(1);

    return (data as List).isNotEmpty;
  }
}
