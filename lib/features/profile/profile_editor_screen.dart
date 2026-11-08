import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';
import '../../providers.dart';
import '../onboarding/onboarding_flow.dart' show AttributeRow, lifestyleIcon;
import '../profile_builder/choice_sheet.dart';
import '../profile_builder/completion_meter.dart';
import '../profile_builder/interest_picker.dart';
import '../profile_builder/music_panel.dart';
import '../profile_builder/photo_grid.dart';
import '../profile_builder/prompt_editor.dart';
import 'profile_detail_screen.dart';

/// Modular profile configuration. Every row saves on its own; prompts save
/// with an explicit button so half-written answers aren't published.
class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key});

  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  List<ProfilePrompt>? _draftPrompts;
  bool _savingPrompts = false;

  Future<void> _save(Map<String, Object?> fields) async {
    try {
      await ref.read(backendProvider).updateProfile(ProfilePatch(fields));
      ref.invalidate(myProfileProvider);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    }
  }

  Future<void> _savePrompts() async {
    final prompts = _draftPrompts;
    if (prompts == null) return;
    final filled = [
      for (final p in prompts)
        if (p.answer.trim().isNotEmpty) p,
    ];
    setState(() => _savingPrompts = true);
    await _save({
      ProfilePatch.prompts: [for (final p in filled) p.toJson()],
    });
    if (mounted) {
      setState(() {
        _savingPrompts = false;
        _draftPrompts = null;
      });
      if (filled.length < promptsMin) showSnack(context, 'Profiles with at least $promptsMin prompts get more replies.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final me = ref.watch(myProfileProvider).value;
    if (me == null) return const Scaffold(body: SizedBox.shrink());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileDetailScreen(profile: me))),
            child: const Text('Preview'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          CompletionMeter(profile: me),
          const SectionLabel('Photos', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
          const PhotoGrid(),

          SectionLabel('Prompts', padding: const EdgeInsets.fromLTRB(4, 26, 4, 10)),
          PromptListEditor(prompts: _draftPrompts ?? me.prompts, onChanged: (v) => setState(() => _draftPrompts = v)),
          if (_draftPrompts != null) ...[
            const SizedBox(height: 10),
            PillButton(label: 'Save prompts', height: 48, busy: _savingPrompts, onTap: _savePrompts),
          ],

          const SectionLabel('About me', padding: EdgeInsets.fromLTRB(4, 26, 4, 6)),
          _Group(
            children: [
              AttributeRow(
                icon: PhosphorIconsRegular.textAa,
                title: 'Bio',
                value: me.bio.isEmpty ? null : me.bio,
                onTap: () async {
                  final v = await showTextSheet(
                    context,
                    title: 'A line about you',
                    hint: 'Weekday coder, weekend trekker…',
                    initial: me.bio,
                    maxLength: 300,
                  );
                  if (v != null) await _save({ProfilePatch.bio: v});
                },
              ),
            ],
          ),

          const SectionLabel('Basics', padding: EdgeInsets.fromLTRB(4, 22, 4, 6)),
          _Group(
            children: [
              AttributeRow(
                icon: PhosphorIconsRegular.user,
                title: 'Gender',
                value: genderLabel(me.gender),
                onTap: () async {
                  final v = await showChoiceSheet(
                    context,
                    title: 'Gender',
                    choices: genders,
                    selected: me.gender,
                    allowClear: false,
                  );
                  if (v != null && v != cleared) await _save({ProfilePatch.gender: v});
                },
              ),
              AttributeRow(
                icon: PhosphorIconsRegular.ruler,
                title: 'Height',
                value: me.heightCm == null ? null : '${me.heightCm} cm',
                onTap: () async {
                  final v = await showHeightSheet(context, initial: me.heightCm);
                  if (v != null) await _save({ProfilePatch.heightCm: v});
                },
              ),
              AttributeRow(
                icon: PhosphorIconsRegular.briefcase,
                title: 'Work',
                value: me.occupation,
                onTap: () async {
                  final v = await showTextSheet(
                    context,
                    title: 'What do you do?',
                    hint: 'e.g. Product designer',
                    initial: me.occupation,
                  );
                  if (v != null) await _save({ProfilePatch.occupation: v.isEmpty ? null : v});
                },
              ),
              AttributeRow(
                icon: PhosphorIconsRegular.graduationCap,
                title: 'Education',
                value: me.education,
                onTap: () async {
                  final v = await showTextSheet(
                    context,
                    title: 'Where did you study?',
                    hint: 'e.g. CET Trivandrum',
                    initial: me.education,
                  );
                  if (v != null) await _save({ProfilePatch.education: v.isEmpty ? null : v});
                },
              ),
              AttributeRow(
                icon: PhosphorIconsRegular.mapPin,
                title: 'Location',
                value: me.city,
                onTap: () async {
                  final v = await showChoiceSheet(
                    context,
                    title: 'Your district',
                    question: 'Only your district or city is shown, never your exact location.',
                    choices: [for (final city in AppConfig.keralaCities) Choice(city, city)],
                    selected: me.city,
                    allowClear: false,
                  );
                  if (v != null && v != cleared) await _save({ProfilePatch.city: v});
                },
              ),
            ],
          ),

          const SectionLabel('How you talk', padding: EdgeInsets.fromLTRB(4, 22, 4, 6)),
          _Group(
            children: [
              AttributeRow(
                icon: PhosphorIconsRegular.identificationBadge,
                title: 'Pronouns',
                value: me.pronouns,
                onTap: () async {
                  final v = await showChoiceSheet(
                    context,
                    title: 'Pronouns',
                    question: 'Shown as a badge on your profile.',
                    choices: [for (final p in pronounOptions) Choice(p, p)],
                    selected: me.pronouns,
                  );
                  if (v != null) await _save({ProfilePatch.pronouns: v == cleared ? null : v});
                },
              ),
              AttributeRow(
                icon: PhosphorIconsRegular.translate,
                title: 'Languages',
                value: me.languages.isEmpty ? null : me.languages.join(', '),
                onTap: () async {
                  final v = await showMultiChoiceSheet(
                    context,
                    title: 'Languages you speak',
                    options: languageOptions,
                    selected: me.languages,
                    max: languagesMax,
                  );
                  if (v != null) await _save({ProfilePatch.languages: v});
                },
              ),
            ],
          ),

          const SectionLabel('Lifestyle', padding: EdgeInsets.fromLTRB(4, 22, 4, 6)),
          _Group(
            children: [
              for (final f in lifestyleFields)
                AttributeRow(
                  icon: lifestyleIcon(f.key),
                  title: f.title,
                  value: f.labelOf(me.lifestyle[f.key]),
                  onTap: () async {
                    final v = await showChoiceSheet(
                      context,
                      title: f.title,
                      question: f.question,
                      choices: f.choices,
                      selected: me.lifestyle[f.key],
                    );
                    if (v == null) return;
                    final next = {...me.lifestyle};
                    v == cleared ? next.remove(f.key) : next[f.key] = v;
                    await _save({ProfilePatch.lifestyle: next});
                  },
                ),
            ],
          ),

          const SectionLabel('Interests', padding: EdgeInsets.fromLTRB(4, 22, 4, 10)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in me.interestTags) TagChip(label: t, selected: true, onTap: () => _editInterests(me)),
              ActionChip(label: Text(me.interestTags.isEmpty ? 'Add interests' : 'Edit'), onPressed: () => _editInterests(me)),
            ],
          ),

          const SectionLabel('Connected accounts', padding: EdgeInsets.fromLTRB(4, 26, 4, 10)),
          const MusicPanel(),
          const SizedBox(height: 12),
          Text(
            'Your profile is visible to signed-in members except people you’ve blocked. '
            'Phone numbers, emails, exact location and social handles are never shown.',
            style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _editInterests(PublicProfile me) async {
    var picked = [...me.interestTags];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (context, scroll) => Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  children: [
                    InterestCounter(count: picked.length),
                    InterestPicker(selected: picked, onChanged: (v) => setSheet(() => picked = v)),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: PillButton(label: 'Save', onTap: () => Navigator.pop(context, true)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _save({ProfilePatch.interestTags: picked});
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.hair),
      ),
      child: Column(children: children),
    );
  }
}
