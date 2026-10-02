import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/review_service.dart';

/// A modal dialog for rating & reviewing a study spot.
///
/// Usage:
/// ```dart
/// final submitted = await showDialog<bool>(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => RatingDialog(studySpotId: reservation.studySpotId),
/// );
/// if (submitted == true) { /* show success message */ }
/// ```
class RatingDialog extends StatefulWidget {
  final String studySpotId;
  final String spotName;

  const RatingDialog({
    super.key,
    required this.studySpotId,
    this.spotName = 'this spot',
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 0;
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a star rating.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await ReviewService.submitReview(
      studySpotId: widget.studySpotId,
      rating: _rating,
      comment: _commentController.text,
    );

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true); // success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Review submitted! Thank you.',
                style: GoogleFonts.inter(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Text(
              'Rate Your Experience',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.spotName,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ── Star selector ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      _rating >= star
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 44,
                      color: _rating >= star
                          ? const Color(0xFFF59E0B)
                          : Colors.grey[300],
                    ),
                  ),
                );
              }),
            ),
            if (_rating > 0) ...[
              const SizedBox(height: 6),
              Text(
                ['', 'Poor', 'Fair', 'Good', 'Great', 'Excellent'][_rating],
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFFF59E0B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Comment field ─────────────────────────────────────────────
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'WiFi speed, ambiance, comfort...',
                hintStyle: GoogleFonts.inter(color: Colors.grey[400]),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                ),
              ),
            ),

            // ── Error message ─────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 20),

            // ── Actions ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Submit Review',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
