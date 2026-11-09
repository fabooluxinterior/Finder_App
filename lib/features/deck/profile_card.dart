import 'package:flutter/material.dart';


import '../../core/brand.dart';
import '../../core/spotify_logo.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';

/// One page of the browsing stack: a photo, or a prompt card placed between
/// photos.
sealed class CardPage {
  const CardPage();
}

class PhotoPage extends CardPage {
  const PhotoPage(this.url);
  final String? url;
}

class PromptPage extends CardPage {
  const PromptPage(this.prompt);
  final ProfilePrompt prompt;
}

/// photo, prompt, photo, prompt, photo, prompt, then the remaining photos.
List<CardPage> cardPages(PublicProfile p) {
  final photos = p.allPhotos;
  final out = <CardPage>[];
  for (var i = 0; i < photos.length || i < p.prompts.length; i++) {
    if (i < photos.length) out.add(PhotoPage(photos[i]));
    if (i < p.prompts.length) out.add(PromptPage(p.prompts[i]));
  }
  if (out.isEmpty) out.add(const PhotoPage(null));
  return out;
}

/// Discover card: framed photo stack with prompt cards between photos (tap
/// the left/right side to move through it), the details and both actions in
/// the card. Tapping a prompt answer starts a reply to that answer.
class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.dragX,
    required this.onTap,
    required this.onPass,
    required this.onRequest,
    this.onReply,
    this.interactive = true,
  });

  final PublicProfile profile;

  /// Horizontal drag in percent (-100..100), from the swiper.
  final int dragX;
  final VoidCallback onTap;
  final VoidCallback onPass;
  final VoidCallback onRequest;
  final ValueChanged<ProfilePrompt>? onReply;

  /// False for the card underneath (cheaper: no buttons).
  final bool interactive;

  static String heroTag(String id) => 'photo-$id';

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  // The card shows only the main photo: tapping it opens the full profile
  // (all photos and prompts are there), it doesn't flip through photos.
  final int _page = 0;
  late List<CardPage> _pages = cardPages(widget.profile).take(1).toList();

  @override
  void didUpdateWidget(ProfileCard old) {
    super.didUpdateWidget(old);
    if (old.profile.id != widget.profile.id) {
      _pages = cardPages(widget.profile).take(1).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final profile = widget.profile;
    // Intent reveals itself as you drag: 0 at rest, 1 at ~45% of the threshold travel.
    final progress = (widget.dragX.abs() / 45).clamp(0.0, 1.0);
    final requesting = widget.dragX > 0;
    final page = _pages[_page];
    final interactive = widget.interactive;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: c.hair),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: AnimatedSwitcher(
                duration: Motion.of(context, const Duration(milliseconds: 160)),
                layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                child: switch (page) {
                  PhotoPage(:final url) when _page == 0 => Hero(
                    key: const ValueKey('p0'),
                    tag: ProfileCard.heroTag(profile.id),
                    child: ProfilePhoto(url: url, name: profile.fullName),
                  ),
                  PhotoPage(:final url) => ProfilePhoto(key: ValueKey('p$_page'), url: url, name: profile.fullName),
                  PromptPage(:final prompt) => _PromptFace(
                    key: ValueKey('q$_page'),
                    prompt: prompt,
                    onReply: interactive && widget.onReply != null ? () => widget.onReply!(prompt) : null,
                  ),
                },
              ),
            ),
            // Night fade carrying the text (static: cached as one layer).
            if (page is PhotoPage)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.4, 0.62, 1],
                      colors: [Color(0x000B0B0C), Color(0xB80B0B0C), Color(0xFF0B0B0C)],
                    ),
                  ),
                ),
              ),
            if (interactive)
              Positioned.fill(
                bottom: 260,
                child: Semantics(
                  button: true,
                  label: 'Open ${profile.firstName}’s profile',
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap),
                ),
              ),
            if (_pages.length > 1)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      for (var i = 0; i < _pages.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: i == _page ? 1 : 0.35),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (interactive) ...[
              // Swipe intent: a transparent ring with an icon, no text.
              Align(
                alignment: const Alignment(0, -0.3),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * progress,
                      child: SwipeIntentIcon(
                        icon: requesting ? VIcons.plus : VIcons.close,
                        color: requesting ? c.accent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: RepaintBoundary(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onTap,
                    child: _Details(
                      profile: profile,
                      compact: page is PromptPage,
                      onPass: widget.onPass,
                      onRequest: widget.onRequest,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A prompt between photos: the question, the answer, and a reply action.
class _PromptFace extends StatelessWidget {
  const _PromptFace({super.key, required this.prompt, this.onReply});
  final ProfilePrompt prompt;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      color: c.surface,
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 220),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prompt.question,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink3),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: onReply != null,
            label: 'Answer: ${prompt.answer}. ${onReply != null ? 'Double tap to reply' : ''}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onReply,
              child: Text(
                prompt.answer,
                style: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.ink),
              ),
            ),
          ),
          if (onReply != null) ...[
            const SizedBox(height: 18),
            Pressable(
              onTap: onReply,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.accent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VIcon(VIcons.chat, size: 18, color: c.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Reply to this',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.profile, required this.onPass, required this.onRequest, this.compact = false});
  final PublicProfile profile;
  final bool compact;
  final VoidCallback onPass;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 42,
                height: 46 / 42,
                fontWeight: FontWeight.w700,
                letterSpacing: -42 * 0.03,
                color: c.ink,
              ),
            ),
            if (profile.isVerified) const VerifiedBadge(size: 28),
            if (profile.isPremium) const FastTrackBadge(large: true),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _Stat(icon: const _Pin(), label: profile.city),
            const SizedBox(width: 18),
            _Stat(
              icon: VIcon(VIcons.photos, size: 17, color: c.muted),
              label: '${profile.photoCount} ${profile.photoCount == 1 ? 'photo' : 'photos'}',
            ),
          ],
        ),
        if (profile.sharedArtists.isNotEmpty || profile.topArtists.isNotEmpty) ...[
          const SizedBox(height: 10),
          MusicAffinityTag(profile: profile),
        ],
        if (profile.bio.isNotEmpty && !compact) ...[
          const SizedBox(height: 10),
          Text(
            profile.bio,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, height: 24 / 17, color: c.ink2),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            RoundButton(
              icon: Icons.close,
              iconWidget: VIcon(VIcons.close, size: 24, color: c.ink, stroke: 2.4),
              size: 60,
              onTap: onPass,
              semanticLabel: 'Pass on ${profile.firstName}',
            ),
            const Spacer(),
            PillButton(
              label: 'Request',
              trailing: VIcon(VIcons.plus, size: 22, color: c.paper, stroke: 2.4),
              expand: false,
              height: 60,
              onTap: onRequest,
            ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin();

  @override
  Widget build(BuildContext context) => VIcon(
    'M12 22s-7-6.4-7-12a7 7 0 0 1 14 0c0 5.6-7 12-7 12zm0-9.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z',
    size: 17,
    color: context.fc.muted,
    fill: true,
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w500, color: c.ink),
        ),
      ],
    );
  }
}

/// Transparent ring with an icon, shown while a card is dragged.
class SwipeIntentIcon extends StatelessWidget {
  const SwipeIntentIcon({super.key, required this.icon, required this.color});
  final String icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.85), width: 2),
    ),
    alignment: Alignment.center,
    child: VIcon(icon, size: 38, color: color, stroke: 2.6),
  );
}

/// "You both listen to …" when there's an overlap; otherwise their top
/// artists in one line. Both come from stored data (no Spotify call).
class MusicAffinityTag extends StatelessWidget {
  const MusicAffinityTag({super.key, required this.profile});
  final PublicProfile profile;

  static const green = Color(0xFF1ED760);

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final shared = profile.sharedArtists;
    if (shared.isNotEmpty) {
      final more = shared.length - 1;
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
        decoration: BoxDecoration(
          color: green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: green.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpotifyLogo(size: 16, semanticLabel: null),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'You both listen to ${shared.first.name}${more > 0 ? ' +$more' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
              ),
            ),
          ],
        ),
      );
    }
    final names = profile.topArtists.take(2).map((a) => a.name).join(', ');
    final more = profile.topArtists.length - 2;
    return Row(
      children: [
        const SpotifyLogo(size: 15, color: Colors.white, semanticLabel: null),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$names${more > 0 ? ' +$more' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14.5, color: c.ink2),
          ),
        ),
      ],
    );
  }
}
