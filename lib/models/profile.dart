import 'profile_catalog.dart';

/// One imported top artist. [visible] only matters on the owner's own list.
class MusicArtist {
  const MusicArtist({required this.id, required this.name, this.image, this.genres = const [], this.visible = true});

  final String id;
  final String name;

  /// Medium-resolution image (Spotify CDN), or null.
  final String? image;
  final List<String> genres;
  final bool visible;

  factory MusicArtist.fromJson(Map<String, dynamic> m) => MusicArtist(
    id: m['id'] as String,
    name: m['name'] as String,
    image: m['image'] as String?,
    genres: ((m['genres'] as List?) ?? const []).cast<String>(),
    visible: (m['visible'] as bool?) ?? true,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'image': image, 'genres': genres};

  MusicArtist copyWith({bool? visible}) =>
      MusicArtist(id: id, name: name, image: image, genres: genres, visible: visible ?? this.visible);
}

/// A structured conversation starter: catalog question + the user's answer.
class ProfilePrompt {
  const ProfilePrompt({required this.promptId, required this.question, required this.answer});

  final String promptId;
  final String question;
  final String answer;

  factory ProfilePrompt.fromJson(Map<String, dynamic> m) {
    final id = m['prompt_id'] as String;
    return ProfilePrompt(
      promptId: id,
      question: (m['question'] as String?) ?? promptById(id)?.question ?? '',
      answer: (m['answer'] as String?) ?? '',
    );
  }

  Map<String, Object?> toJson() => {'prompt_id': promptId, 'answer': answer};
}

class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.fullName,
    required this.age,
    required this.city,
    required this.bio,
    required this.primaryPhoto,
    required this.isPremium,
    this.isVerified = false,
    this.photoCount = 1,
    this.photos = const [],
    this.prompts = const [],
    this.interestTags = const [],
    this.occupation,
    this.education,
    this.heightCm,
    this.gender,
    this.pronouns,
    this.languages = const [],
    this.lifestyle = const {},
    this.topArtists = const [],
    this.sharedArtistIds = const [],
    this.sharedInterestCount = 0,
    this.completionScore = 0,
    this.onboardingStage = 1,
    this.isOnboarded = false,
    this.musicLinked = false,
  });

  final String id;
  final String fullName;
  final int age;
  final String city;
  final String bio;

  /// Resolved (displayable) URL of the primary photo, or null.
  final String? primaryPhoto;
  final bool isPremium;

  /// Set only by a moderator after selfie verification (server-side).
  final bool isVerified;
  final int photoCount;

  /// All photos in slot order (resolved URLs). The first is [primaryPhoto].
  final List<String> photos;
  final List<ProfilePrompt> prompts;
  final List<String> interestTags;
  final String? occupation;
  final String? education;
  final int? heightCm;
  final String? gender;
  final String? pronouns;
  final List<String> languages;

  /// lifestyle key -> value (see [lifestyleFields]).
  final Map<String, String> lifestyle;

  /// Publicly visible top artists (hidden ones are never sent).
  final List<MusicArtist> topArtists;

  /// Artists this profile shares with the viewer (computed server-side).
  final List<String> sharedArtistIds;
  final int sharedInterestCount;

  /// Server-computed 0–100 (see profile_completion.dart).
  final int completionScore;
  final int onboardingStage;
  final bool isOnboarded;
  final bool musicLinked;

  String get firstName => fullName.split(' ').first;

  List<MusicArtist> get sharedArtists => topArtists.where((a) => sharedArtistIds.contains(a.id)).toList();

  /// Photos for display, falling back to the primary photo for older rows.
  List<String> get allPhotos => photos.isNotEmpty ? photos : [?primaryPhoto];

  PublicProfile copyWith({
    String? primaryPhoto,
    bool? isPremium,
    bool? isVerified,
    List<String>? photos,
    List<ProfilePrompt>? prompts,
    List<String>? interestTags,
    String? fullName,
    String? city,
    String? bio,
    String? occupation,
    String? education,
    int? heightCm,
    String? gender,
    String? pronouns,
    List<String>? languages,
    Map<String, String>? lifestyle,
    List<MusicArtist>? topArtists,
    List<String>? sharedArtistIds,
    int? sharedInterestCount,
    int? completionScore,
    int? onboardingStage,
    bool? isOnboarded,
    bool? musicLinked,
    int? age,
    bool clearOccupation = false,
    bool clearEducation = false,
    bool clearHeight = false,
    bool clearPronouns = false,
  }) {
    final ph = photos ?? this.photos;
    return PublicProfile(
      id: id,
      fullName: fullName ?? this.fullName,
      age: age ?? this.age,
      city: city ?? this.city,
      bio: bio ?? this.bio,
      primaryPhoto: photos != null ? (ph.isEmpty ? null : ph.first) : (primaryPhoto ?? this.primaryPhoto),
      isPremium: isPremium ?? this.isPremium,
      isVerified: isVerified ?? this.isVerified,
      photoCount: photos != null ? ph.length : photoCount,
      photos: ph,
      prompts: prompts ?? this.prompts,
      interestTags: interestTags ?? this.interestTags,
      occupation: clearOccupation ? null : (occupation ?? this.occupation),
      education: clearEducation ? null : (education ?? this.education),
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      gender: gender ?? this.gender,
      pronouns: clearPronouns ? null : (pronouns ?? this.pronouns),
      languages: languages ?? this.languages,
      lifestyle: lifestyle ?? this.lifestyle,
      topArtists: topArtists ?? this.topArtists,
      sharedArtistIds: sharedArtistIds ?? this.sharedArtistIds,
      sharedInterestCount: sharedInterestCount ?? this.sharedInterestCount,
      completionScore: completionScore ?? this.completionScore,
      onboardingStage: onboardingStage ?? this.onboardingStage,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      musicLinked: musicLinked ?? this.musicLinked,
    );
  }

  static List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) =>
      ((v as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();

  /// Rows from get_feed / get_profile_card. [resolve] maps media ids to URLs.
  factory PublicProfile.fromFeedRow(Map<String, dynamic> m, {String Function(String)? resolve}) {
    final r = resolve ?? (String s) => s;
    final photos = ((m['photo_urls'] as List?) ?? const []).cast<String>().map(r).toList();
    final primary = m['primary_photo'] as String?;
    return PublicProfile(
      id: m['id'] as String,
      fullName: m['full_name'] as String,
      age: (m['age'] as num).toInt(),
      city: m['city'] as String,
      bio: (m['bio'] as String?) ?? '',
      primaryPhoto: primary == null ? null : r(primary),
      isPremium: (m['is_premium'] as bool?) ?? false,
      isVerified: (m['is_verified'] as bool?) ?? false,
      photoCount: (m['photo_count'] as num?)?.toInt() ?? photos.length,
      photos: photos,
      prompts: _list(m['prompts'], ProfilePrompt.fromJson),
      interestTags: ((m['interest_tags'] as List?) ?? const []).cast<String>(),
      occupation: m['occupation'] as String?,
      education: m['education'] as String?,
      heightCm: (m['height_cm'] as num?)?.toInt(),
      gender: m['gender'] as String?,
      pronouns: m['pronouns'] as String?,
      languages: ((m['languages'] as List?) ?? const []).cast<String>(),
      lifestyle: ((m['lifestyle_attributes'] as Map?) ?? const {}).cast<String, String>(),
      topArtists: _list(m['music_top_artists'], MusicArtist.fromJson),
      sharedArtistIds: ((m['shared_artist_ids'] as List?) ?? const []).cast<String>(),
      sharedInterestCount: (m['shared_interest_count'] as num?)?.toInt() ?? 0,
      musicLinked: ((m['music_top_artists'] as List?) ?? const []).isNotEmpty,
    );
  }

  /// The caller's own `profiles` row.
  factory PublicProfile.fromProfileRow(Map<String, dynamic> m, {String Function(String)? resolve}) {
    final r = resolve ?? (String s) => s;
    final avatar = ((m['avatar_urls'] as List?) ?? const []).cast<String>();
    final photos = ((m['photo_urls'] as List?) ?? const []).cast<String>().map(r).toList();
    final primary = photos.isNotEmpty ? photos.first : (avatar.isEmpty ? null : r(avatar.first));
    return PublicProfile(
      id: m['id'] as String,
      fullName: m['full_name'] as String,
      age: (m['age'] as num).toInt(),
      city: m['city'] as String,
      bio: (m['bio'] as String?) ?? '',
      primaryPhoto: primary,
      isPremium: (m['is_premium'] as bool?) ?? false,
      isVerified: (m['is_verified'] as bool?) ?? false,
      photoCount: photos.length,
      photos: photos,
      prompts: _list(m['prompts'], ProfilePrompt.fromJson),
      interestTags: ((m['interest_tags'] as List?) ?? const []).cast<String>(),
      occupation: m['occupation'] as String?,
      education: m['education'] as String?,
      heightCm: (m['height_cm'] as num?)?.toInt(),
      gender: m['gender'] as String?,
      pronouns: m['pronouns'] as String?,
      languages: ((m['languages'] as List?) ?? const []).cast<String>(),
      lifestyle: ((m['lifestyle_attributes'] as Map?) ?? const {}).cast<String, String>(),
      topArtists: _list(m['music_top_artists'], MusicArtist.fromJson),
      completionScore: (m['completion_score'] as num?)?.toInt() ?? 0,
      onboardingStage: (m['onboarding_stage'] as num?)?.toInt() ?? 1,
      isOnboarded: (m['is_onboarded'] as bool?) ?? false,
      musicLinked: (m['music_linked'] as bool?) ?? false,
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

/// One of the owner's photo slots (approved, or still in review).
class PhotoSlot {
  const PhotoSlot({required this.mediaId, required this.url, this.pending = false});
  final String mediaId;
  final String url;
  final bool pending;
}

enum MusicStatus { disconnected, active, reauthRequired }

/// The owner's music connection (never includes tokens).
class MusicState {
  const MusicState({this.status = MusicStatus.disconnected, this.artists = const [], this.syncedAt});
  final MusicStatus status;

  /// Imported top artists with their visibility.
  final List<MusicArtist> artists;
  final DateTime? syncedAt;

  bool get connected => status != MusicStatus.disconnected;
  static const disconnected = MusicState();
}
