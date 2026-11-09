import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../deck/profile_card.dart';
import '../onboarding/onboarding_flow.dart' show lifestyleIcon;
import '../profile_builder/icebreaker_sheet.dart';
import '../profile_builder/spotify_card.dart';
import '../../core/phosphor.dart';
import '../../models/profile_catalog.dart';
import '../safety/safety_actions.dart';

/// Profile visit: photos and interests are visible to every signed-in user
/// (not blocked). Contact details and exact location are never part of a
/// profile; only the district/city is shown.
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({super.key, required this.profile, this.onPass, this.onRequest, this.onReplied});
  final PublicProfile profile;

  /// Called after a prompt reply was sent from this screen (the deck then
  /// moves on without sending a second request).
  final VoidCallback? onReplied;

  /// Provided when opened from the Discover deck.
  final VoidCallback? onPass;
  final VoidCallback? onRequest;

  @override
  ConsumerState<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  int _photo = 0;

  PublicProfile get profile => ref.watch(profileCardProvider(widget.profile.id)).value ?? widget.profile;

  Future<void> _reply(ProfilePrompt prompt) async {
    final outcome = await showIcebreakerSheet(context, profile, prompt);
    if (outcome == null || !mounted) return;
    Navigator.pop(context);
    if (widget.onReplied != null) {
      Future.delayed(const Duration(milliseconds: 120), widget.onReplied);
    }
    ref.invalidate(feedProvider);
  }

  void _act(VoidCallback? f) {
    Navigator.pop(context);
    // Let the pop start before the card leaves the deck.
    Future.delayed(const Duration(milliseconds: 120), f);
  }

  Future<void> _report() async {
    if (await showReportSheet(context, profile) && mounted) Navigator.pop(context);
  }

  Future<void> _block() async {
    if (await confirmBlock(context, ref, profile) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final backend = ref.watch(backendProvider);
    final myId = backend.currentUserId;
    final isMe = profile.id == myId;
    final mine = isMe ? null : ref.watch(myProfileProvider).value;
    final connected = ref.watch(connectionsProvider).value?.any((x) => x.profile.id == profile.id) ?? false;
    final fromDeck = widget.onPass != null && widget.onRequest != null;
    final showActions = fromDeck && !connected && !isMe;
    final top = MediaQuery.paddingOf(context).top;
    final screen = MediaQuery.sizeOf(context);

    // The first photo leads; the rest alternate with prompts below.
    final all = profile.allPhotos;
    final photos = <String?>[all.isEmpty ? null : all.first];
    final index = _photo.clamp(0, photos.length - 1);
    final common = mine == null ? <String>{} : profile.interestTags.toSet().intersection(mine.interestTags.toSet());
    final extra = all.skip(1).toList();
    final canReply = !isMe && !connected;
    final prompts = profile.prompts;

    Widget promptCard(ProfilePrompt p) => _PromptCard(prompt: p, onReply: canReply ? () => _reply(p) : null);
    final interleaved = <Widget>[
      for (var i = 0; i < prompts.length || i < extra.length; i++) ...[
        if (i < prompts.length) promptCard(prompts[i]),
        if (i == 0) _BasicsSection(profile: profile),
        if (i < extra.length) _PhotoCard(url: extra[i], name: profile.fullName),
        if (i == 1 && SpotifyProfileCard.hasContent(profile)) SpotifyProfileCard(profile: profile),
      ],
      if (prompts.isEmpty && extra.isEmpty) _BasicsSection(profile: profile),
      if (SpotifyProfileCard.hasContent(profile) && prompts.length < 2 && extra.length < 2) SpotifyProfileCard(profile: profile),
    ];

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(bottom: showActions ? 112 : 40),
            children: [
              // ---- photo section
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                child: SizedBox(
                  height: (screen.height * 0.64).clamp(420.0, 620.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: Motion.of(context, const Duration(milliseconds: 220)),
                        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                        child: index == 0
                            ? Hero(
                                key: const ValueKey(0),
                                tag: ProfileCard.heroTag(profile.id),
                                child: ProfilePhoto(url: photos[0], name: profile.fullName),
                              )
                            : ProfilePhoto(key: ValueKey(index), url: photos[index], name: profile.fullName),
                      ),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0, 0.16, 0.7, 1],
                              colors: [Color(0x66000000), Color(0x00000000), Color(0x000B0B0C), Color(0xFF0B0B0C)],
                            ),
                          ),
                        ),
                      ),
                      // Tap the left / right half to step through photos.
                      if (photos.length > 1)
                        Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                button: true,
                                label: 'Previous photo',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _photo = (index - 1).clamp(0, photos.length - 1)),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Semantics(
                                button: true,
                                label: 'Next photo',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _photo = (index + 1).clamp(0, photos.length - 1)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (photos.length > 1)
                        Positioned(
                          top: top + 8,
                          left: 16,
                          right: 16,
                          child: ExcludeSemantics(
                            child: Row(
                              children: [
                                for (var i = 0; i < photos.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 4),
                                  Expanded(
                                    child: AnimatedContainer(
                                      duration: Motion.of(context, Motion.fast),
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: i == index ? 1 : 0.4),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: IgnorePointer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: profile.firstName),
                                        TextSpan(
                                          text: ' ${profile.age}',
                                          style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFFC9C9CF)),
                                        ),
                                      ],
                                    ),
                                    style: TextStyle(
                                      fontSize: 40,
                                      height: 44 / 40,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1.2,
                                      color: c.ink,
                                    ),
                                  ),
                                  if (profile.isVerified) const VerifiedBadge(size: 26),
                                  if (profile.isPremium) const FastTrackBadge(large: true),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  VIcon(
                                    'M12 22s-7-6.4-7-12a7 7 0 0 1 14 0c0 5.6-7 12-7 12zm0-9.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
                                    size: 17,
                                    color: c.muted,
                                    fill: true,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    profile.city,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.ink),
                                  ),
                                  if (connected) ...[
                                    const SizedBox(width: 16),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Connected',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.ink),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // ---- details
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (profile.bio.isNotEmpty) _Section(title: 'About', child: _Body(profile.bio)),
                    ...interleaved,
                    if (profile.interestTags.isNotEmpty)
                      _Section(
                        title: 'Interests',
                        trailing: common.isEmpty ? null : '${common.length} in common',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final i in profile.interestTags)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  color: common.contains(i) ? c.accentSoft : c.paper,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: common.contains(i) ? c.accent : c.hair),
                                ),
                                child: Text(
                                  i,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: common.contains(i) ? const Color(0xFFFF8A73) : c.ink,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    _Section(
                      title: null,
                      child: Row(
                        children: [
                          profile.isVerified
                              ? const VerifiedBadge(size: 30)
                              : VIcon(VIcons.done, size: 26, color: c.muted, stroke: 2.4),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.isVerified ? 'Photo verified' : 'Not verified yet',
                                  style: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, color: c.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  backend.isEndToEndEncrypted
                                      ? 'Chats stay end-to-end encrypted and screenshots are blocked.'
                                      : 'Screenshots are blocked in chats.',
                                  style: TextStyle(fontSize: 14, height: 20 / 14, color: c.ink3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isMe)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _report,
                              child: Text(
                                'Report ${profile.firstName}',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink3),
                              ),
                            ),
                            Text('·', style: TextStyle(color: c.muted)),
                            TextButton(
                              onPressed: _block,
                              child: Text(
                                'Block',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink3),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Floating top controls over the photo.
          Positioned(
            top: top + 20,
            left: 12,
            right: 12,
            child: Row(
              children: [
                RoundButton(
                  icon: Icons.arrow_back,
                  iconWidget: VIcon(VIcons.back, size: 22, color: Colors.white),
                  glass: true,
                  size: 44,
                  onTap: () => Navigator.pop(context),
                  semanticLabel: 'Back',
                ),
                const Spacer(),
                if (!isMe)
                  PopupMenuButton<String>(
                    color: c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: c.hair),
                    ),
                    onSelected: (v) => v == 'report' ? _report() : _block(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'report', child: Text('Report')),
                      PopupMenuItem(value: 'block', child: Text('Block ${profile.firstName}')),
                    ],
                    child: IgnorePointer(
                      child: RoundButton(
                        icon: Icons.more_horiz,
                        iconWidget: VIcon(VIcons.more, size: 22, color: Colors.white),
                        glass: true,
                        size: 44,
                        onTap: _noop,
                        semanticLabel: 'More options',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showActions)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.paddingOf(context).bottom + 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.35],
                    colors: [c.paper.withValues(alpha: 0), c.paper],
                  ),
                ),
                child: Row(
                  children: [
                    RoundButton(
                      icon: Icons.close,
                      iconWidget: VIcon(VIcons.close, size: 24, color: c.ink, stroke: 2.4),
                      size: 60,
                      onTap: () => _act(widget.onPass),
                      semanticLabel: 'Pass on ${profile.firstName}',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: 'Request',
                        height: 60,
                        trailing: VIcon(VIcons.plus, size: 22, color: c.paper, stroke: 2.4),
                        onTap: () => _act(widget.onRequest),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _noop() {}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});
  final String? title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, color: c.muted),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFFF7A62)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 18, height: 27 / 18, color: context.fc.ink),
  );
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.url, required this.name});
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ProfilePhoto(url: url, name: name),
      ),
    ),
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, this.onReply});
  final ProfilePrompt prompt;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return GestureDetector(
      onTap: onReply,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prompt.question,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink3),
            ),
            const SizedBox(height: 10),
            Text(
              prompt.answer,
              style: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.ink),
            ),
            if (onReply != null)
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(
                  button: true,
                  label: 'Reply to this answer',
                  child: Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.accent),
                    ),
                    child: Center(child: VIcon(VIcons.chat, size: 20, color: c.accent)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Height, work, education, pronouns, languages and lifestyle as badges.
class _BasicsSection extends StatelessWidget {
  const _BasicsSection({required this.profile});
  final PublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final items = <(IconData, String)>[
      if (profile.heightCm != null) (PhosphorIconsRegular.ruler, '${profile.heightCm} cm'),
      if (profile.occupation != null) (PhosphorIconsRegular.briefcase, profile.occupation!),
      if (profile.education != null) (PhosphorIconsRegular.graduationCap, profile.education!),
      if (profile.pronouns != null) (PhosphorIconsRegular.identificationBadge, profile.pronouns!),
      if (profile.languages.isNotEmpty) (PhosphorIconsRegular.translate, profile.languages.join(', ')),
      for (final f in lifestyleFields)
        if (f.labelOf(profile.lifestyle[f.key]) != null) (lifestyleIcon(f.key), f.labelOf(profile.lifestyle[f.key])!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Basics',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label) in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: c.hair),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: c.ink3),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, style: TextStyle(fontSize: 14.5, color: c.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
