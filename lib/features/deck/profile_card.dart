import 'package:flutter/material.dart';

import '../../core/phosphor.dart';

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
    final t = Theme.of(context).textTheme;
    // Intent reveals itself as you drag: 0 at rest, 1 at ~45% of the threshold travel.
    final progress = (dragX.abs() / 45).clamp(0.0, 1.0);
    final requesting = dragX > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: c.hair),
          // One modest shadow: large blur radii are expensive on a moving layer.
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.09), blurRadius: 18, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FrostedPhoto(
                url: profile.primaryPhoto,
                name: profile.fullName,
                color: c.surface,
                heroTag: heroTag(profile.id),
                blur: interactive,
              ),
              if (interactive) ...[
                // Swipe intent: a transparent glass ring with a white icon, no text.
                Align(
                  alignment: const Alignment(0, -0.25),
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: progress,
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * progress,
                        child: _SwipeIcon(icon: requesting ? PhosphorIconsFill.userPlus : PhosphorIconsBold.x),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 16,
                  bottom: 18,
                  // Static while dragging: cache it as its own layer.
                  child: RepaintBoundary(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: profile.firstName),
                                    TextSpan(
                                      text: '  ${profile.age}',
                                      style: TextStyle(fontWeight: FontWeight.w400, color: c.ink2),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.headlineMedium?.copyWith(fontSize: 28),
                              ),
                            ),
                            if (profile.isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 20)],
                            if (profile.isPremium) ...[const SizedBox(width: 6), const FastTrackBadge()],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _Stat(icon: PhosphorIconsFill.mapPin, label: profile.city),
                            const SizedBox(width: 14),
                            _Stat(icon: PhosphorIconsFill.imagesSquare, label: '${profile.photoCount} photos'),
                          ],
                        ),
                        if (profile.bio.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(profile.bio, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            RoundButton(icon: PhosphorIconsBold.x, onTap: onPass, semanticLabel: 'Pass'),
                            const Spacer(),
                            PillButton(
                              label: 'Request',
                              trailingIcon: PhosphorIconsBold.plus,
                              dark: false,
                              expand: false,
                              height: 46,
                              onTap: onRequest,
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c.muted),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.ink)),
      ],
    );
  }
}

class _SwipeIcon extends StatelessWidget {
  const _SwipeIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    height: 84,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.78), width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 16)],
    ),
    child: Icon(
      icon,
      size: 36,
      color: Colors.white,
      shadows: const [Shadow(color: Color(0x40000000), blurRadius: 8)],
    ),
  );
}
