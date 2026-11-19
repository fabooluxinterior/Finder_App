/// A profile detail introduced after launch that this user hasn't filled in
/// yet (server: public.my_profile_updates). Existing data is never touched;
/// the app only asks for what's missing.
class ProfileUpdate {
  const ProfileUpdate({
    required this.key,
    required this.label,
    required this.description,
    this.form = 'basics',
    this.level = ProfileUpdateLevel.optional,
    this.gatedFeature,
    this.showPrompt = true,
  });

  final String key;
  final String label;
  final String description;

  /// Which editor section opens ("basics", ...).
  final String form;
  final ProfileUpdateLevel level;

  /// Only this feature waits for the detail (null: nothing is locked).
  final String? gatedFeature;

  /// False while dismissed or recently shown (the server decides).
  final bool showPrompt;

  bool get optional => level == ProfileUpdateLevel.optional;

  factory ProfileUpdate.fromJson(Map<String, dynamic> m) => ProfileUpdate(
    key: m['key'] as String,
    label: m['label'] as String,
    description: m['description'] as String,
    form: (m['form'] as String?) ?? 'basics',
    level: ProfileUpdateLevel.values.firstWhere((l) => l.name == m['level'], orElse: () => ProfileUpdateLevel.optional),
    gatedFeature: m['gated_feature'] as String?,
    showPrompt: (m['show_prompt'] as bool?) ?? true,
  );
}

enum ProfileUpdateLevel { optional, feature, required }

/// Summary for the You tab.
enum ProfileUpdateSummary { complete, required, optional }

ProfileUpdateSummary summarizeUpdates(List<ProfileUpdate> updates) {
  if (updates.isEmpty) return ProfileUpdateSummary.complete;
  return updates.any((u) => !u.optional) ? ProfileUpdateSummary.required : ProfileUpdateSummary.optional;
}
