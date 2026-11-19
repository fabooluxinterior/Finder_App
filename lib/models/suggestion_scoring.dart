import 'profile.dart';
import 'profile_catalog.dart';
import 'suggestion.dart';

/// Default weights (adjustable on the server in recommendation_config).
const defaultSuggestionWeights = {
  'interests': 0.35,
  'music': 0.20,
  'lifestyle': 0.15,
  'hobbies': 0.15,
  'location': 0.10,
  'completeness': 0.05,
};
const youMayLikeWeights = {'music': 0.45, 'hobbies': 0.35, 'interests': 0.20};
const hobbyCategories = {'Active & sports', 'Creative arts', 'Gaming'};

/// Dart mirror of `public.suggestion_score` (the offline demo uses it; the
/// server's version is authoritative). Music counts only when both people
/// linked Spotify, so it's never required.
({int score, List<SuggestionReason> reasons}) scoreSuggestion(
  PublicProfile me,
  PublicProfile o, {
  Map<String, double> weights = defaultSuggestionWeights,
}) {
  var total = 0.0, wSum = 0.0;
  final reasons = <SuggestionReason>[];
  double w(String k) => weights[k] ?? 0;
  void add(String k, double s) {
    if (w(k) <= 0) return;
    total += w(k) * s;
    wSum += w(k);
  }

  int minOf(int a, int b, int cap) => [a, b, cap].reduce((x, y) => x < y ? x : y);

  // interests
  final shared = me.interestTags.where(o.interestTags.contains).toList();
  final mi = minOf(me.interestTags.length, o.interestTags.length, 5);
  add('interests', mi == 0 ? 0 : (shared.length / mi).clamp(0, 1).toDouble());
  if (shared.isNotEmpty) reasons.add(SuggestionReason(kind: 'interests', items: shared.take(5).toList(), count: shared.length));

  // hobbies
  final hobbyTags = {
    for (final c in interestCategories)
      if (hobbyCategories.contains(c.title)) ...c.tags,
  };
  final mh = me.interestTags.where(hobbyTags.contains).toList();
  final th = o.interestTags.where(hobbyTags.contains).toList();
  final sh = mh.where(th.contains).length;
  if (mh.isNotEmpty || th.isNotEmpty) {
    final m = minOf(mh.length, th.length, 3);
    add('hobbies', m == 0 ? 0 : (sh / m).clamp(0, 1).toDouble());
  }

  // music (visible artists only)
  if (me.musicLinked && o.musicLinked && me.topArtists.isNotEmpty && o.topArtists.isNotEmpty) {
    final mine = {for (final a in me.topArtists) a.id};
    final both = o.topArtists.where((a) => mine.contains(a.id)).map((a) => a.name).toList();
    final m = minOf(me.topArtists.length, o.topArtists.length, 3);
    add('music', (both.length / m).clamp(0, 1).toDouble());
    if (both.isNotEmpty) reasons.add(SuggestionReason(kind: 'music', items: both, count: both.length));
  }

  // lifestyle
  final keys = me.lifestyle.keys.where(o.lifestyle.containsKey).toList();
  final same = keys.where((k) => me.lifestyle[k] == o.lifestyle[k]).toList();
  if (keys.isNotEmpty) add('lifestyle', same.length / keys.length);
  if (same.isNotEmpty) reasons.add(SuggestionReason(kind: 'lifestyle', items: same, count: same.length));

  // location (same district; no GPS)
  final sameCity = me.city.toLowerCase() == o.city.toLowerCase();
  add('location', sameCity ? 1 : 0);
  if (sameCity) reasons.add(SuggestionReason(kind: 'city', items: [o.city]));

  // completeness
  add('completeness', o.completionScore / 100);

  return (score: wSum == 0 ? 0 : (100 * total / wSum).round(), reasons: reasons);
}

/// Both people fit each other's discovery preferences.
bool prefsMatch(PublicProfile a, PublicProfile b) =>
    b.age >= a.prefAgeMin &&
    b.age <= a.prefAgeMax &&
    a.age >= b.prefAgeMin &&
    a.age <= b.prefAgeMax &&
    (a.prefGenders.isEmpty || (b.gender != null && a.prefGenders.contains(b.gender))) &&
    (b.prefGenders.isEmpty || (a.gender != null && b.prefGenders.contains(a.gender)));
