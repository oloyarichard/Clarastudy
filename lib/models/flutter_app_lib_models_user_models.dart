import '../core/network/api_config.dart';
import 'parsing_utils.dart';

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.phoneNumber,
    this.profilePicture,
    this.bio,
    this.country,
    this.city,
    this.isVerified = false,
    this.createdAt,
  });

  final String id;
  final String email;
  final String username;
  final String firstName;
  final String lastName;
  final String role;
  final String? phoneNumber;
  final String? profilePicture;
  final String? bio;
  final String? country;
  final String? city;
  final bool isVerified;
  final DateTime? createdAt;

  String get fullName => '$firstName $lastName'.trim();
  String get displayName => fullName.isNotEmpty ? fullName : username;

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isAdmin => role == 'admin';

  String get profilePictureUrl => ApiConfig.resolveMediaUrl(profilePicture);

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: parseString(json['id']),
      email: parseString(json['email']),
      username: parseString(json['username']),
      firstName: parseString(json['first_name']),
      lastName: parseString(json['last_name']),
      role: parseString(json['role'], fallback: 'student'),
      phoneNumber: json['phone_number'] as String?,
      profilePicture: json['profile_picture'] as String?,
      bio: json['bio'] as String?,
      country: json['country'] as String?,
      city: json['city'] as String?,
      isVerified: parseBool(json['is_verified']),
      createdAt: parseDate(json['created_at']),
    );
  }

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? bio,
    String? country,
    String? city,
    String? profilePicture,
  }) {
    return AppUser(
      id: id,
      email: email,
      username: username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicture: profilePicture ?? this.profilePicture,
      bio: bio ?? this.bio,
      country: country ?? this.country,
      city: city ?? this.city,
      isVerified: isVerified,
      createdAt: createdAt,
    );
  }
}

class TeacherProfile {
  TeacherProfile({
    required this.id,
    required this.user,
    this.qualifications,
    this.specialization,
    this.yearsOfExperience = 0,
    this.hourlyRate = 0,
    this.rating = 0,
    this.totalReviews = 0,
    this.isApproved = false,
  });

  final String id;
  final AppUser user;
  final String? qualifications;
  final String? specialization;
  final int yearsOfExperience;
  final double hourlyRate;
  final double rating;
  final int totalReviews;
  final bool isApproved;

  factory TeacherProfile.fromJson(Map<String, dynamic> json) {
    return TeacherProfile(
      id: parseString(json['id']),
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
      qualifications: json['qualifications'] as String?,
      specialization: json['specialization'] as String?,
      yearsOfExperience: parseInt(json['years_of_experience']),
      hourlyRate: parseDouble(json['hourly_rate']),
      rating: parseDouble(json['rating']),
      totalReviews: parseInt(json['total_reviews']),
      isApproved: parseBool(json['is_approved']),
    );
  }
}
