import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../services/profile_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies:
//
//   image_picker: ^1.1.2
//   flutter_image_compress: ^2.2.0
//   path_provider: ^2.1.4
//   path: ^1.9.0
//
// Android — add inside <application> in AndroidManifest.xml:
//   <activity android:name="com.yalantis.ucrop.UCropActivity"
//             android:screenOrientation="portrait"
//             android:theme="@style/Theme.AppCompat.Light.NoActionBar"/>
//
// iOS — add to Info.plist:
//   <key>NSPhotoLibraryUsageDescription</key>
//   <string>Select a profile picture</string>
//   <key>NSCameraUsageDescription</key>
//   <string>Take a profile picture</string>
// ─────────────────────────────────────────────────────────────────────────────

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();

  String? _currentAvatarUrl; // URL already saved in Supabase Storage
  File? _pendingImageFile; // locally-picked, not yet uploaded
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      // ensureProfileExists() guarantees a row in public.users.
      // If this is the user's first time opening Edit Profile after sign-up
      // and the row doesn't exist yet, the fields would all be empty without it.
      await ProfileService.ensureProfileExists();
      final profile = await ProfileService.getProfile();
      if (mounted) {
        setState(() {
          if (profile != null) {
            _firstNameController.text = profile.firstName;
            _surnameController.text = profile.surname;
            _phoneController.text = profile.phoneNumber ?? '';
            _emailController.text = profile.email;
            _bioController.text = profile.bio ?? '';
            _currentAvatarUrl = profile.profilePictureUrl;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Error loading profile: $e');
      }
    }
  }

  // ── Image picker ───────────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final source = await _showImageSourceDialog();
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    final compressed = await _compressImage(File(picked.path));
    if (compressed != null && mounted) {
      setState(() => _pendingImageFile = compressed);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text('Choose from gallery', style: GoogleFonts.inter()),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text('Take a photo', style: GoogleFonts.inter()),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  /// Compress [source] to JPEG at 85% quality, max 800×800 px (≤ ~200 KB).
  Future<File?> _compressImage(File source) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath = p.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}_avatar.jpg',
      );
      final result = await FlutterImageCompress.compressAndGetFile(
        source.absolute.path,
        targetPath,
        quality: 85,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.jpeg,
      );
      return result != null ? File(result.path) : null;
    } catch (_) {
      return null; // fall back to the original if compression fails
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    final firstName = _firstNameController.text.trim();
    final surname = _surnameController.text.trim();
    final newEmail = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (firstName.isEmpty || surname.isEmpty) {
      _showSnack('First name and surname are required.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 1. Upload new avatar if the user picked one.
      if (_pendingImageFile != null) {
        final url = await ProfileService.uploadProfilePicture(
          _pendingImageFile!,
        );
        if (mounted) setState(() => _currentAvatarUrl = url);
      }

      // 2. Persist text field changes.
      await ProfileService.updateProfile(
        firstName: firstName,
        surname: surname,
        phoneNumber: phone.isEmpty ? null : phone,
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
      );

      // 3. Update email only if it actually changed.
      final currentProfile = await ProfileService.getProfile();
      final currentEmail = currentProfile?.email ?? '';
      if (newEmail.isNotEmpty && newEmail != currentEmail) {
        await ProfileService.updateEmail(newEmail);
        if (mounted) {
          _showSnack(
            'A confirmation link was sent to $newEmail. '
            'Your email will update after you confirm.',
            duration: const Duration(seconds: 6),
          );
        }
      }

      if (!mounted) return;
      _showSnack('Profile updated successfully!');
      Navigator.pop(context, true); // signal ProfileScreen to reload
    } catch (e) {
      if (mounted) _showSnack('Error saving profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(
    String msg, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), duration: duration));
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'Edit Profile',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // ── Avatar picker ────────────────────────────────────────
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: primaryColor.withValues(alpha: 0.12),
                          backgroundImage: _pendingImageFile != null
                              ? FileImage(_pendingImageFile!) as ImageProvider
                              : (_currentAvatarUrl != null
                                    ? NetworkImage(_currentAvatarUrl!)
                                    : null),
                          child:
                              (_pendingImageFile == null &&
                                  _currentAvatarUrl == null)
                              ? Icon(
                                  Icons.person,
                                  size: 52,
                                  color: primaryColor,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to change photo',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── First Name ───────────────────────────────────────────
                  _buildTextField(
                    'First Name',
                    _firstNameController,
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),

                  // ── Surname ──────────────────────────────────────────────
                  _buildTextField(
                    'Surname',
                    _surnameController,
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),

                  // ── Phone Number ─────────────────────────────────────────
                  _buildTextField(
                    'Phone Number',
                    _phoneController,
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  // ── Email (with login warning) ───────────────────────────
                  _buildTextField(
                    'Email Address',
                    _emailController,
                    Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    helperText:
                        '⚠ This is your login email. '
                        'Changing it sends a confirmation link.',
                  ),
                  const SizedBox(height: 16),

                  // ── Bio ──────────────────────────────────────────────────
                  _buildTextField(
                    'Bio',
                    _bioController,
                    Icons.info_outline,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 40),

                  // ── Save button ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        disabledBackgroundColor: primaryColor.withValues(
                          alpha: 0.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Save Changes',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? helperText,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        helperStyle: GoogleFonts.inter(fontSize: 11, color: Colors.orange[700]),
        labelStyle: GoogleFonts.inter(color: Colors.grey[600]),
        prefixIcon: maxLines == 1 ? Icon(icon, color: Colors.grey[400]) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor),
        ),
      ),
    );
  }
}
