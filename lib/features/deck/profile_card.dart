import 'package:flutter/material.dart';

import '../../core/brand.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';

/// Discover card: white rim, full-bleed photo, frosted fade carrying the
/// text, and the two actions inside the card.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.dragX,
    required this.onTap,
    required this.onPass,
    required this.onRequest,
    this.interactive = true,
  });

  final PublicProfile profile;

  /// Horizontal drag in percent (-100..100), from the swiper.
  final int dragX;
  final VoidCallback onTap;
  final VoidCallback onPass;
  final VoidCallback onRequest;

  /// False for the card underneath (cheaper: no blur, no buttons).
  final bool interactive;

  static String heroTag(String id) => 'photo-$id';

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    // Intent reveals itself as you drag: 0 at rest, 1 at ~45% of the threshold travel.
    final progress = (dragX.abs() / 45).clamp(0.0, 1.0);
    final requesting = dragX > 0;
    final bars = profile.photoCount.clamp(1, 7);

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                child: Hero(
                  tag: heroTag(profile.id),
                  child: ProfilePhoto(url: profile.primaryPhoto, name: profile.fullName),
                ),
              ),
              // Night fade carrying the text (static: cached as one layer).
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
              if (bars > 1)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var i = 0; i < bars; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: i == 0 ? 1 : 0.4),
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
                        child: _SwipeIcon(
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
                    child: _Details(profile: profile, onPass: onPass, onRequest: onRequest),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.profile, required this.onPass, required this.onRequest});
  final PublicProfile profile;
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
        if (profile.bio.isNotEmpty) ...[
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

class _SwipeIcon extends StatelessWidget {
  const _SwipeIcon({required this.icon, required this.color});
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
