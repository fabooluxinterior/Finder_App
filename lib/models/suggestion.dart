import 'profile.dart';
import 'profile_catalog.dart';

/// One explainable shared signal behind a suggestion.
class SuggestionReason {
  const SuggestionReason({required this.kind, this.items = const [], this.count = 0});

  /// interests | music | lifestyle | city
  final String kind;
  final List<String> items;
  final int count;

  factory SuggestionReason.fromJson(Map<String, dynamic> m) => SuggestionReason(
    kind: m['kind'] as String,
    items: ((m['items'] as List?) ?? const []).map((e) => '$e').toList(),
    count: (m['count'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {'kind': kind, 'items': items, 'count': count};

  /// Plain-language explanation shown on the card.
  String get label => switch (kind) {
    'interests' => count == 1 ? 'You both like ${items.first}' : '$count shared interests',
    'music' => 'You both listen to ${items.first}${count > 1 ? ' +${count - 1}' : ''}',
    'lifestyle' =>
      'Same answer on ${items.map((k) => lifestyleFields.where((f) => f.key == k).firstOrNull?.title.toLowerCase() ?? k).join(' and ')}',
    'city' => 'Also in ${items.first}',
    _ => '',
  };
}

class Suggestion {
  const Suggestion({required this.profile, required this.compatibility, required this.reasons, this.section = 'main'});
  final PublicProfile profile;

  /// 0–100 from weighted shared signals (see suggestion_score in SQL).
  final int compatibility;
  final List<SuggestionReason> reasons;
  final String section;

  /// Shared interests, for chips on the card.
  List<String> get sharedInterests => reasons.where((r) => r.kind == 'interests').expand((r) => r.items).toList();
}

class SuggestionStatus {
  const SuggestionStatus({required this.dailyLimit, required this.shownToday, required this.remaining, this.resetsAt});
  final int dailyLimit;
  final int shownToday;
  final int remaining;
  final DateTime? resetsAt;
}
