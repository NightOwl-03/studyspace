/// Maps to public.users table.
class UserProfile {
  final String id;
  final String firstName;
  final String? middleName;
  final String surname;
  final String email;
  final String? phoneNumber;
  final String? profilePictureUrl;
  final String? bio;
  final int totalPoints;
  final String accountStatus;

  const UserProfile({
    required this.id,
    required this.firstName,
    this.middleName,
    required this.surname,
    required this.email,
    this.phoneNumber,
    this.profilePictureUrl,
    this.bio,
    required this.totalPoints,
    required this.accountStatus,
  });

  String get fullName => [
    firstName,
    if (middleName != null && middleName!.isNotEmpty) middleName,
    surname,
  ].join(' ');

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      middleName: map['middle_name'] as String?,
      surname: map['surname'] as String,
      email: map['email'] as String,
      phoneNumber: map['phone_number'] as String?,
      // Always use getPublicUrl-style strings stored in the DB column.
      profilePictureUrl: map['profile_picture_url'] as String?,
      bio: map['bio'] as String?,
      totalPoints: (map['total_points'] as num?)?.toInt() ?? 0,
      accountStatus: map['account_status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toUpdateMap() => {
    'first_name': firstName,
    'middle_name': middleName,
    'surname': surname,
    'phone_number': phoneNumber,
    'bio': bio,
    'updated_at': DateTime.now().toIso8601String(),
  };
}
