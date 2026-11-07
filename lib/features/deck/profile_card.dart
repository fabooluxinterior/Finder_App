import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.dragX,
    required this.dragY,
    required this.onTap,
  });

  final PublicProfile profile;

  /// Drag offsets in percent (-100..100) supplied by the swiper.
  final int dragX;
  final int dragY;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final follow = (dragX / 60).clamp(0.0, 1.0);
    final pass = (-dragX / 60).clamp(0.0, 1.0);
    final note = (dragY.abs() > dragX.abs() && dragY < 0) ? (-dragY / 60).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProfilePhoto(url: profile.primaryPhoto, name: profile.fullName),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Colors.transparent, Color(0xE6000000)],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${profile.firstName}, ${profile.age}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      if (profile.isPremium) ...[const SizedBox(width: 8), const FastTrackBadge()],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(profile.city, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  ]),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      profile.bio,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock_outline, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Photos & interests unlock after follow',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ),
            ),
            if (follow > 0) _Stamp(label: 'FOLLOW', color: AppColors.brand, opacity: follow, alignment: Alignment.topLeft, angle: -0.25),
            if (pass > 0) _Stamp(label: 'PASS', color: AppColors.pass, opacity: pass, alignment: Alignment.topRight, angle: 0.25),
            if (note > 0) _Stamp(label: '⭐ NOTE', color: AppColors.gold, opacity: note, alignment: Alignment.center, angle: 0),
          ],
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.alignment,
    required this.angle,
  });

  final String label;
  final Color color;
  final double opacity;
  final Alignment alignment;
  final double angle;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: angle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(label,
                    style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
              ),
            ),
          ),
        ),
      );
}
