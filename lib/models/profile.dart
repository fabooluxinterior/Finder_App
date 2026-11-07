class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.fullName,
    required this.age,
    required this.city,
    required this.bio,
    required this.primaryPhoto,
    required this.isPremium,
  });

  final String id;
  final String fullName;
  final int age;
  final String city;
  final String bio;

  /// Resolved (displayable) URL of the primary photo, or null.
  final String? primaryPhoto;
  final bool isPremium;

  String get firstName => fullName.split(' ').first;

  PublicProfile copyWith({String? primaryPhoto, bool? isPremium}) => PublicProfile(
        id: id,
        fullName: fullName,
        age: age,
        city: city,
        bio: bio,
        primaryPhoto: primaryPhoto ?? this.primaryPhoto,
        isPremium: isPremium ?? this.isPremium,
      );

  factory PublicProfile.fromFeedRow(Map<String, dynamic> m) => PublicProfile(
        id: m['id'] as String,
        fullName: m['full_name'] as String,
        age: (m['age'] as num).toInt(),
        city: m['city'] as String,
        bio: (m['bio'] as String?) ?? '',
        primaryPhoto: m['primary_photo'] as String?,
        isPremium: (m['is_premium'] as bool?) ?? false,
      );

  factory PublicProfile.fromProfileRow(Map<String, dynamic> m) {
    final urls = (m['avatar_urls'] as List?)?.cast<String>() ?? const [];
    return PublicProfile(
      id: m['id'] as String,
      fullName: m['full_name'] as String,
      age: (m['age'] as num).toInt(),
      city: m['city'] as String,
      bio: (m['bio'] as String?) ?? '',
      primaryPhoto: urls.isEmpty ? null : urls.first,
      isPremium: (m['is_premium'] as bool?) ?? false,
    );
  }
}

/// Data that unlocks only after a follow request is accepted.
class PrivateProfile {
  const PrivateProfile({required this.interests, required this.gallery});
  final List<String> interests;

  /// Resolved (displayable) gallery URLs.
  final List<String> gallery;

  static const empty = PrivateProfile(interests: [], gallery: []);
}
