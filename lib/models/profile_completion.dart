import 'profile.dart';
import 'profile_catalog.dart';

/// Profile completion, 0–100. Mirrors `public.profile_completion` in SQL
/// exactly (the server value is authoritative; this drives live UI).
///   photos 7.5 each up to 4 (30) · occupation 5 + education 5 (10)
///   lifestyle: 6 selections + languages, 20 × n/7 (20)
///   interests 3 each up to 5 (15) · bio ≥20 chars (10)
///   prompts 5 each up to 2 (10) · music linked (5)
class ProfileCompletion {
  const ProfileCompletion._(this.score, this.nextStep, this.parts);

  final int score;

  /// What to do next, or null when complete.
  final String? nextStep;

  /// Section -> (earned, max) for breakdowns.
  final Map<String, (double, double)> parts;

  static int compute({
    required int photos,
    String? occupation,
    String? education,
    int lifestyleCount = 0,
    int languages = 0,
    int tags = 0,
    String bio = '',
    int prompts = 0,
    bool music = false,
  }) {
    final v =
        (photos.clamp(0, 4) * 7.5) +
        ((occupation ?? '').trim().isNotEmpty ? 5 : 0) +
        ((education ?? '').trim().isNotEmpty ? 5 : 0) +
        20.0 * (lifestyleCount + (languages > 0 ? 1 : 0)) / 7 +
        tags.clamp(0, 5) * 3 +
        (bio.trim().length >= 20 ? 10 : 0) +
        prompts.clamp(0, 2) * 5 +
        (music ? 5 : 0);
    // Postgres round(numeric) rounds halves away from zero; so does Dart.
    return v.round();
  }

  factory ProfileCompletion.of(PublicProfile p) {
    final lifestyle = p.lifestyle.length + (p.languages.isNotEmpty ? 1 : 0);
    final parts = <String, (double, double)>{
      'photos': (p.photoCount.clamp(0, 4) * 7.5, 30),
      'work': (((p.occupation ?? '').isNotEmpty ? 5.0 : 0.0) + ((p.education ?? '').isNotEmpty ? 5.0 : 0.0), 10),
      'lifestyle': (20.0 * lifestyle / 7, 20),
      'interests': (p.interestTags.length.clamp(0, 5) * 3.0, 15),
      'bio': (p.bio.trim().length >= 20 ? 10.0 : 0.0, 10),
      'prompts': (p.prompts.length.clamp(0, 2) * 5.0, 10),
      'music': (p.musicLinked ? 5.0 : 0.0, 5),
    };
    final score = compute(
      photos: p.photoCount,
      occupation: p.occupation,
      education: p.education,
      lifestyleCount: p.lifestyle.length,
      languages: p.languages.length,
      tags: p.interestTags.length,
      bio: p.bio,
      prompts: p.prompts.length,
      music: p.musicLinked,
    );
    String? next;
    if (p.photoCount < photosMin) {
      final n = photosMin - p.photoCount;
      next = 'Add $n more photo${n == 1 ? '' : 's'} (+${(n * 7.5).round()}%)';
    } else if (p.prompts.length < promptsMin) {
      next = 'Answer ${promptsMin - p.prompts.length} more prompt${promptsMin - p.prompts.length == 1 ? '' : 's'}';
    } else if (p.interestTags.length < interestsMin) {
      next = 'Pick ${interestsMin - p.interestTags.length} more interests';
    } else if (p.bio.trim().length < 20) {
      next = 'Write a short bio (+10%)';
    } else if (lifestyle < 7) {
      next = 'Fill in your lifestyle details';
    } else if ((p.occupation ?? '').isEmpty || (p.education ?? '').isEmpty) {
      next = 'Add your work and education';
    } else if (!p.musicLinked) {
      next = 'Connect Spotify (+5%)';
    }
    return ProfileCompletion._(score, next, parts);
  }
}
