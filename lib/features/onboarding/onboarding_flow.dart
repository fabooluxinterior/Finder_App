import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';
import '../../providers.dart';
import '../profile_builder/choice_sheet.dart';
import '../profile_builder/completion_meter.dart';
import '../profile_builder/interest_picker.dart';
import '../profile_builder/music_panel.dart';
import '../profile_builder/photo_grid.dart';
import '../profile_builder/prompt_editor.dart';
import 'dob.dart';

/// First-run setup in seven stages. Progress is saved on the profile
/// (`onboarding_stage`) after every stage, so leaving and coming back resumes
/// where you stopped. The server decides when the profile can go live.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, this.profile});
  final PublicProfile? profile;

  static const stages = 7;
  static const titles = [
    'How Vouby works',
    'About you',
    'Your everyday',
    'What you’re into',
    'Your photos',
    'Conversation starters',
    'Almost there',
  ];

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late int _stage = widget.profile == null ? 1 : widget.profile!.onboardingStage.clamp(1, OnboardingFlow.stages);
  bool _busy = false;
  final _scroll = ScrollController();

  // Stage 2
  late final _name = TextEditingController(text: widget.profile?.fullName ?? '');
  DateTime? _dob;
  bool _hasDob = false;
  late String? _gender = widget.profile?.gender;
  late int? _height = widget.profile?.heightCm;
  late String? _occupation = widget.profile?.occupation;
  late String? _education = widget.profile?.education;
  late String _city = widget.profile?.city ?? AppConfig.keralaCities.first;

  // Stage 3
  late final Map<String, String> _lifestyle = {...?widget.profile?.lifestyle};
  late List<String> _languages = [...?widget.profile?.languages];

  // Stage 4
  late List<String> _tags = [...?widget.profile?.interestTags];

  // Stage 6
  late List<ProfilePrompt> _prompts = [...?widget.profile?.prompts];
  late final _bio = TextEditingController(text: widget.profile?.bio ?? '');

  @override
  void initState() {
    super.initState();
    ref
        .read(backendProvider)
        .hasDob()
        .then((v) {
          if (mounted) setState(() => _hasDob = v);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _scroll.dispose();
    super.dispose();
  }

  FinderBackend get _backend => ref.read(backendProvider);

  bool get _canContinue => switch (_stage) {
    2 => _name.text.trim().length >= 2 && (_hasDob || _dob != null) && _gender != null,
    4 => _tags.length >= interestsMin,
    5 => (ref.watch(photoSlotsProvider).value ?? const []).where((s) => !s.pending).length >= photosMin,
    6 =>
      _prompts.where((p) => p.answer.trim().isNotEmpty).length >= promptsMin &&
          !_prompts.any((p) => p.answer.trim().length > promptAnswerMax || ContactSanitizer.containsContactInfo(p.answer)) &&
          !ContactSanitizer.containsContactInfo(_bio.text),
    _ => true,
  };

  String get _blockedReason => switch (_stage) {
    2 => 'Add your name, birthdate and gender to continue.',
    4 => 'Pick at least $interestsMin interests.',
    5 => 'Add at least $photosMin photos.',
    6 => 'Answer at least $promptsMin prompts.',
    _ => '',
  };

  Future<void> _next() async {
    if (_busy) return;
    if (!_canContinue) {
      showSnack(context, _blockedReason);
      return;
    }
    setState(() => _busy = true);
    try {
      switch (_stage) {
        case 1:
          await _backend.acknowledgeStandards(AppConfig.policyVersion);
        case 2:
          if (!_hasDob && _dob != null) {
            await _backend.setDob(_dob!);
            _hasDob = true;
          }
          await _backend.createProfile(
            fullName: _name.text.trim(),
            city: _city,
            details: ProfilePatch({
              ProfilePatch.gender: _gender,
              ProfilePatch.heightCm: _height,
              ProfilePatch.occupation: _occupation,
              ProfilePatch.education: _education,
              ProfilePatch.onboardingStage: 3,
            }),
          );
        case 3:
          await _backend.updateProfile(
            ProfilePatch({
              ProfilePatch.lifestyle: _lifestyle,
              ProfilePatch.languages: _languages,
              ProfilePatch.onboardingStage: 4,
            }),
          );
        case 4:
          await _backend.updateProfile(ProfilePatch({ProfilePatch.interestTags: _tags, ProfilePatch.onboardingStage: 5}));
        case 5:
          await _backend.updateProfile(const ProfilePatch({ProfilePatch.onboardingStage: 6}));
        case 6:
          await _backend.updateProfile(
            ProfilePatch({
              ProfilePatch.prompts: [
                for (final p in _prompts)
                  if (p.answer.trim().isNotEmpty) p.toJson(),
              ],
              ProfilePatch.bio: _bio.text.trim(),
              ProfilePatch.onboardingStage: 7,
            }),
          );
        case 7:
          await _backend.completeOnboarding();
          ref.invalidate(myProfileProvider);
          ref.invalidate(feedProvider);
          return;
      }
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      setState(() => _stage++);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_stage > 1) setState(() => _stage--);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: _stage == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: _stage > 1
                          ? IconButton(
                              tooltip: 'Back',
                              onPressed: _busy ? null : _back,
                              icon: VIcon(VIcons.back, size: 22, color: c.ink),
                            )
                          : null,
                    ),
                    Expanded(
                      child: _ProgressBar(stage: _stage, total: OnboardingFlow.stages),
                    ),
                    const SizedBox(width: 12),
                    Text('$_stage/${OnboardingFlow.stages}', style: TextStyle(fontSize: 13, color: c.muted)),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  switchInCurve: Motion.easeOut,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_stage),
                    child: ListView(
                      controller: _scroll,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      children: [
                        Text(
                          OnboardingFlow.titles[_stage - 1],
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._stageBody(context),
                      ],
                    ),
                  ),
                ),
              ),
              if (!keyboard || _stage != 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: PillButton(
                    label: switch (_stage) {
                      1 => 'I agree',
                      7 => 'Finish and start exploring',
                      _ => 'Continue',
                    },
                    height: 56,
                    busy: _busy,
                    onTap: _canContinue ? _next : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stageBody(BuildContext context) => switch (_stage) {
    1 => _standards(context),
    2 => _identity(context),
    3 => _routine(context),
    4 => _interests(context),
    5 => _photos(context),
    6 => _promptsStage(context),
    _ => _finish(context),
  };

  // ---------------------------------------------------------------- 1
  List<Widget> _standards(BuildContext context) {
    final c = context.fc;
    const principles = [
      (
        PhosphorIconsFill.sealCheck,
        'Be the real you',
        'Your own name, your own recent photos, your real age. Verified profiles get a blue tick.',
      ),
      (
        PhosphorIconsFill.handshake,
        'Both people say yes',
        'Chats open only when a request is accepted. A pass, an unmatch or a block is an answer; respect it.',
      ),
      (
        PhosphorIconsFill.chatsCircle,
        'Talk like you would in person',
        'Lead with curiosity. No pressure for photos, numbers or plans you haven’t both agreed to.',
      ),
      (
        PhosphorIconsFill.shieldCheck,
        'Keep each other safe',
        'No money requests, no sharing chats without consent. Report anything that feels wrong; it’s anonymous.',
      ),
    ];
    return [
      Text('A few principles everyone here agrees to.', style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3)),
      const SizedBox(height: 20),
      for (final (icon, title, body) in principles)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.hair),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c.accent, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: TextStyle(fontSize: 14.5, height: 1.45, color: c.ink3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 4),
      Text(
        'Breaking these can get a profile removed. Full rules are in the Community Guidelines.',
        style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
      ),
    ];
  }

  // ---------------------------------------------------------------- 2
  List<Widget> _identity(BuildContext context) {
    final c = context.fc;
    return [
      Text(
        'Your first name is shown on your profile. Your birthdate stays private.',
        style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: 60,
        decoration: const InputDecoration(labelText: 'Name', helperText: 'As on your ID. Only your first name is shown.'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      if (_hasDob)
        InfoChip(icon: PhosphorIconsRegular.cake, label: 'Birthdate saved · age from your birthdate')
      else ...[
        DobField(value: _dob, onChanged: (d) => setState(() => _dob = d)),
        if (_dob != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'You’ll show as ${ageOn(_dob!, DateTime.now())}. This can’t be changed later.',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
      ],
      const SectionLabel('Gender', padding: EdgeInsets.fromLTRB(2, 20, 2, 10)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in genders)
            TagChip(label: g.label, selected: _gender == g.value, onTap: () => setState(() => _gender = g.value)),
        ],
      ),
      const SectionLabel('Details', padding: EdgeInsets.fromLTRB(2, 22, 2, 8)),
      AttributeRow(
        icon: PhosphorIconsRegular.ruler,
        title: 'Height',
        value: _height == null ? null : '$_height cm',
        onTap: () async {
          final v = await showHeightSheet(context, initial: _height);
          if (v != null) setState(() => _height = v);
        },
      ),
      AttributeRow(
        icon: PhosphorIconsRegular.briefcase,
        title: 'Work',
        value: _occupation,
        onTap: () async {
          final v = await showTextSheet(context, title: 'What do you do?', hint: 'e.g. Product designer', initial: _occupation);
          if (v != null) setState(() => _occupation = v.isEmpty ? null : v);
        },
      ),
      AttributeRow(
        icon: PhosphorIconsRegular.graduationCap,
        title: 'Education',
        value: _education,
        onTap: () async {
          final v = await showTextSheet(context, title: 'Where did you study?', hint: 'e.g. CET Trivandrum', initial: _education);
          if (v != null) setState(() => _education = v.isEmpty ? null : v);
        },
      ),
      AttributeRow(
        icon: PhosphorIconsRegular.mapPin,
        title: 'Location',
        value: _city,
        onTap: () async {
          final v = await showChoiceSheet(
            context,
            title: 'Your district',
            question: 'Only your district or city is shown, never your exact location.',
            choices: [for (final city in AppConfig.keralaCities) Choice(city, city)],
            selected: _city,
            allowClear: false,
          );
          if (v != null && v != cleared) setState(() => _city = v);
        },
      ),
    ];
  }

  // ---------------------------------------------------------------- 3
  List<Widget> _routine(BuildContext context) {
    final c = context.fc;
    return [
      Text(
        'All optional, all changeable later. Each one you add helps the right people find you.',
        style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3),
      ),
      const SizedBox(height: 16),
      for (final f in lifestyleFields)
        AttributeRow(
          icon: lifestyleIcon(f.key),
          title: f.title,
          value: f.labelOf(_lifestyle[f.key]),
          onTap: () async {
            final v = await showChoiceSheet(
              context,
              title: f.title,
              question: f.question,
              choices: f.choices,
              selected: _lifestyle[f.key],
            );
            if (v == null) return;
            setState(() => v == cleared ? _lifestyle.remove(f.key) : _lifestyle[f.key] = v);
          },
        ),
      AttributeRow(
        icon: PhosphorIconsRegular.translate,
        title: 'Languages',
        value: _languages.isEmpty ? null : _languages.join(', '),
        onTap: () async {
          final v = await showMultiChoiceSheet(
            context,
            title: 'Languages you speak',
            options: languageOptions,
            selected: _languages,
            max: languagesMax,
          );
          if (v != null) setState(() => _languages = v);
        },
      ),
    ];
  }

  // ---------------------------------------------------------------- 4
  List<Widget> _interests(BuildContext context) {
    final c = context.fc;
    return [
      Text(
        'Pick at least $interestsMin. Shared interests are highlighted when you browse.',
        style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3),
      ),
      const SizedBox(height: 10),
      InterestCounter(count: _tags.length),
      InterestPicker(selected: _tags, onChanged: (v) => setState(() => _tags = v)),
    ];
  }

  // ---------------------------------------------------------------- 5
  List<Widget> _photos(BuildContext context) {
    final c = context.fc;
    return [
      Text(
        'Add $photosMin to $maxPhotoSlots recent photos of you. They’re resized and compressed on your phone '
        'before upload, then checked before anyone sees them.',
        style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3),
      ),
      const SizedBox(height: 18),
      const PhotoGrid(),
    ];
  }

  // ---------------------------------------------------------------- 6
  List<Widget> _promptsStage(BuildContext context) {
    final c = context.fc;
    return [
      Text(
        'Answer at least $promptsMin. People can reply to an answer directly, so specific beats clever.',
        style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3),
      ),
      const SizedBox(height: 18),
      PromptListEditor(prompts: _prompts, onChanged: (v) => setState(() => _prompts = v)),
      const SectionLabel('A line about you (optional)', padding: EdgeInsets.fromLTRB(2, 24, 2, 8)),
      TextField(
        controller: _bio,
        maxLength: 300,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Weekday coder, weekend trekker…',
          errorText: ContactSanitizer.containsContactInfo(_bio.text) ? 'Contact details aren’t allowed' : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  // ---------------------------------------------------------------- 7
  List<Widget> _finish(BuildContext context) {
    final c = context.fc;
    final me = ref.watch(myProfileProvider).value;
    return [
      Text('Link your music if you like, then you’re ready.', style: TextStyle(fontSize: 16, height: 1.45, color: c.ink3)),
      const SizedBox(height: 18),
      const MusicPanel(),
      const SizedBox(height: 14),
      if (me != null) CompletionMeter(profile: me),
    ];
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.stage, required this.total});
  final int stage;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      label: 'Step $stage of $total',
      child: Row(
        children: [
          for (var i = 1; i <= total; i++) ...[
            if (i > 1) const SizedBox(width: 4),
            Expanded(
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.medium),
                height: 4,
                decoration: BoxDecoration(color: i <= stage ? c.accent : c.hair, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData lifestyleIcon(String key) => switch (key) {
  'intention' => PhosphorIconsRegular.heart,
  'activity' => PhosphorIconsRegular.barbell,
  'drinking' => PhosphorIconsRegular.wine,
  'smoking' => PhosphorIconsRegular.cigarette,
  'zodiac' => PhosphorIconsRegular.moonStars,
  _ => PhosphorIconsRegular.globeHemisphereEast,
};

/// Grouped list row: icon, attribute title, current value and a caret.
class AttributeRow extends StatelessWidget {
  const AttributeRow({super.key, required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      semanticLabel: '$title: ${value ?? 'not set'}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 21, color: c.ink3),
            const SizedBox(width: 14),
            Text(title, style: TextStyle(fontSize: 16, color: c.ink)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? 'Add',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: value == null ? c.accent : c.ink3,
                  fontWeight: value == null ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: c.muted),
          ],
        ),
      ),
    );
  }
}
