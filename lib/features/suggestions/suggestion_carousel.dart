import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/suggestion.dart';
import '../deck/profile_card.dart' show MusicAffinityTag;
import 'suggestions_screen.dart' show CompatibilityBadge;

/// "Best matches for you": big photo cards you swipe sideways. The photo is the whole card (no border);
/// the name, city and shared interests sit on a dark gradient at the bottom, with Request on top of the
/// photo. The card in the middle is full size, its neighbours slightly smaller.
class SuggestionCarousel extends StatefulWidget {
  const SuggestionCarousel({super.key, required this.items, required this.onOpen, required this.onRequest, required this.onPass});
  final List<Suggestion> items;
  final ValueChanged<Suggestion> onOpen;
  final ValueChanged<Suggestion> onRequest;
  final ValueChanged<Suggestion> onPass;

  @override
  State<SuggestionCarousel> createState() => _SuggestionCarouselState();
}

class _SuggestionCarouselState extends State<SuggestionCarousel> {
  final _pc = PageController(viewportFraction: 0.84);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  double get _page => _pc.hasClients && _pc.position.haveDimensions ? (_pc.page ?? 0) : 0;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final n = widget.items.length;
    return Column(
      children: [
        SizedBox(
          height: 540,
          child: PageView.builder(
            controller: _pc,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            itemCount: n,
            itemBuilder: (context, i) => AnimatedBuilder(
              animation: _pc,
              builder: (context, child) {
                final d = (_page - i).abs().clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 1 - 0.06 * d,
                  child: Opacity(opacity: 1 - 0.25 * d, child: child),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: _CarouselCard(
                  suggestion: widget.items[i],
                  onTap: () => widget.onOpen(widget.items[i]),
                  onRequest: () => widget.onRequest(widget.items[i]),
                  onPass: () => widget.onPass(widget.items[i]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _pc,
          builder: (context, _) {
            final at = _page.round().clamp(0, n - 1);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < n && i < 12; i++)
                  AnimatedContainer(
                    duration: Motion.of(context, const Duration(milliseconds: 280)),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == at ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: i == at ? c.accent : c.hair, borderRadius: BorderRadius.circular(3)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.suggestion, required this.onTap, required this.onRequest, required this.onPass});
  final Suggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback onRequest;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    final p = suggestion.profile;
    final tags = suggestion.sharedInterests.take(3).toList();
    final reasons = suggestion.reasons.where((r) => r.kind != 'interests' && r.kind != 'music').take(2).toList();
    return Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      semanticLabel: '${p.firstName}, ${p.age}, ${suggestion.compatibility}% match',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ProfilePhoto(url: p.primaryPhoto, name: p.fullName, decodeWidth: 700),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 360,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.45, 1],
                    colors: [Color(0x000B0B0C), Color(0xC70B0B0C), Color(0xF00B0B0C)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Semantics(
                button: true,
                label: 'Pass on ${p.firstName}',
                child: GestureDetector(
                  onTap: onPass,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
            Positioned(top: 12, right: 12, child: CompatibilityBadge(value: suggestion.compatibility)),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${p.firstName}, ${p.age}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (p.isVerified) ...[const SizedBox(width: 8), const VerifiedBadge(size: 21)],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(PhosphorIconsFill.mapPin, size: 15, color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 5),
                      Text(p.city, style: TextStyle(fontSize: 14.5, color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                  if (p.bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      p.bio,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, height: 1.35, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.17),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (p.sharedArtists.isNotEmpty || p.topArtists.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    MusicAffinityTag(profile: p),
                  ],
                  for (final r in reasons)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          VIcon(VIcons.done, size: 15, color: context.fc.ok, stroke: 2.4),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(r.label, style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.85))),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  PillButton(label: 'Request', onTap: onRequest),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
