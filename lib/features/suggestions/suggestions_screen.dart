import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../models/profile.dart';
import '../../models/suggestion.dart';
import '../../providers.dart';
import '../deck/profile_card.dart' show MusicAffinityTag, SwipeIntentIcon;
import '../match/match_screen.dart';
import '../profile/profile_detail_screen.dart';
import 'discovery_preferences_screen.dart';

/// "People you might like": server-ranked suggestions with the reasons
/// behind each one, plus a "You may like" row. Swipe a card right to send a
/// request or left to pass (icons only, no text), or tap it for the profile.
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  static const pageMax = 20;
  static const pageStep = 10;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

enum _Load { loading, ready, offline, error }

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  _Load _state = _Load.loading;
  List<Suggestion> _main = [];
  List<Suggestion> _mayLike = [];
  SuggestionStatus? _status;
  bool _loadingMore = false;
  bool _loaded = false;

  /// Everyone shown in this session (for "next page").
  final _seen = <String>{};

  /// Sliding cards for the best matches: index of the card on top.
  final _swiper = CardSwiperController();
  int _top = 0;

  @override
  void dispose() {
    _swiper.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _state = _Load.loading);
    final backend = ref.read(backendProvider);
    try {
      final main = await backend.suggestions(limit: SuggestionsScreen.pageStep);
      final mayLike = await backend.suggestions(
        section: 'you_may_like',
        limit: 6,
        exclude: main.map((s) => s.profile.id).toList(),
      );
      final status = await backend.suggestionStatus();
      if (!mounted) return;
      setState(() {
        _main = main;
        _top = 0;
        _mayLike = mayLike;
        _status = status;
        _seen.addAll([...main, ...mayLike].map((s) => s.profile.id));
        _state = _Load.ready;
        _loaded = true;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _state = e.code == AppErrorCode.network ? _Load.offline : _Load.error);
    } catch (_) {
      if (mounted) setState(() => _state = _Load.error);
    }
  }

  /// Adds 10 more (to a page of 20), or starts the next page.
  Future<void> _more({bool nextPage = false}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final backend = ref.read(backendProvider);
    try {
      final more = await backend.suggestions(
        limit: SuggestionsScreen.pageStep,
        exclude: (nextPage ? _seen : {..._main.map((s) => s.profile.id), ..._mayLike.map((s) => s.profile.id)}).toList(),
      );
      final status = await backend.suggestionStatus();
      if (!mounted) return;
      setState(() {
        if (nextPage || _top >= _main.length) {
          _main = more;
          _top = 0;
        } else {
          _main = [..._main, ...more];
        }
        _seen.addAll(more.map((s) => s.profile.id));
        _status = status;
      });
      if (more.isEmpty) showSnack(context, status.remaining == 0 ? 'That’s all for today.' : 'No more suggestions right now.');
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _remove(String id) => setState(() {
    _main.removeWhere((s) => s.profile.id == id);
    _mayLike.removeWhere((s) => s.profile.id == id);
  });

  Future<void> _act(PublicProfile p, {required bool follow}) async {
    _remove(p.id);
    await _send(p, follow: follow);
  }

  Future<void> _send(PublicProfile p, {required bool follow}) async {
    follow ? Fx.instance.request() : Fx.instance.pass();
    try {
      final outcome = await ref.read(backendProvider).swipe(p.id, follow: follow);
      ref.invalidate(feedProvider);
      if (outcome == SwipeOutcome.matched && mounted) {
        ref.invalidate(connectionsProvider);
        final me = await ref.read(myProfileProvider.future);
        if (mounted) await showMatch(context, me: me, them: p);
      }
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    }
  }

  bool _onSwipe(int previous, int? current, CardSwiperDirection direction) {
    final p = _main[previous].profile;
    setState(() => _top = current ?? _main.length);
    _send(p, follow: direction == CardSwiperDirection.right);
    return true;
  }

  bool _isTop(Suggestion s) => _top < _main.length && _main[_top].profile.id == s.profile.id;

  void _open(Suggestion s) {
    // From the top sliding card, Pass/Request in the profile slide it away.
    final top = _isTop(s);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(
          profile: s.profile,
          onPass: () => top ? _swiper.swipe(CardSwiperDirection.left) : _act(s.profile, follow: false),
          onRequest: () => top ? _swiper.swipe(CardSwiperDirection.right) : _act(s.profile, follow: true),
          onReplied: () => top ? setState(() => _top++) : _remove(s.profile.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final bottomBar = MediaQuery.paddingOf(context).bottom;
    final status = _status;
    // Someone you connect with (from anywhere) disappears from Suggestions.
    ref.listen<AsyncValue<List<Connection>>>(connectionsProvider, (prev, next) {
      final ids = next.value?.map((x) => x.profile.id).toSet() ?? const <String>{};
      if (ids.isEmpty) return;
      if (_main.any((s) => ids.contains(s.profile.id)) || _mayLike.any((s) => ids.contains(s.profile.id))) {
        setState(() {
          _main.removeWhere((s) => ids.contains(s.profile.id));
          _mayLike.removeWhere((s) => ids.contains(s.profile.id));
        });
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          // A refresh brings back today's suggestions; it never resets the allowance.
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('People you might like', style: t.headlineMedium?.copyWith(fontSize: 30)),
                            const SizedBox(height: 4),
                            Text(
                              'Discover people who share your interests.',
                              style: TextStyle(fontSize: 15, height: 22 / 15, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      RoundButton(
                        icon: Icons.tune,
                        iconWidget: VIcon(VIcons.settings, size: 21, color: c.ink),
                        size: 44,
                        semanticLabel: 'Discovery preferences',
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoveryPreferencesScreen()));
                          if (mounted) _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              ..._body(context, status, bottomBar),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, SuggestionStatus? status, double bottomBar) {
    switch (_state) {
      case _Load.loading when !_loaded:
        return [const SliverToBoxAdapter(child: _Skeleton())];
      case _Load.offline:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: PhosphorIconsRegular.wifiSlash,
              title: 'You’re offline',
              body: 'Suggestions need a connection. Check it and try again.',
              action: 'Try again',
              onAction: _load,
              bottom: bottomBar,
            ),
          ),
        ];
      case _Load.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: PhosphorIconsRegular.warningCircle,
              title: 'Couldn’t load suggestions',
              body: 'Something went wrong on our side. Try again in a moment.',
              action: 'Try again',
              onAction: _load,
              bottom: bottomBar,
            ),
          ),
        ];
      default:
        break;
    }

    if (_main.isEmpty && _mayLike.isEmpty) {
      final limitReached = status != null && status.remaining == 0;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: limitReached
              ? _Message(
                  icon: PhosphorIconsRegular.hourglass,
                  title: 'That’s today’s suggestions',
                  body: 'You’ve seen your ${status.dailyLimit} for today. New ones arrive tomorrow. Discover is always open.',
                  bottom: bottomBar,
                )
              : _Message(
                  icon: PhosphorIconsRegular.sparkle,
                  title: 'No new suggestions right now',
                  body: 'Add interests or prompts, connect Spotify, or widen your preferences to see more people.',
                  action: 'Discovery preferences',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoveryPreferencesScreen()),
                  ).then((_) => _load()),
                  bottom: bottomBar,
                ),
        ),
      ];
    }

    final c = context.fc;
    return [
      if (_mayLike.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionLabel('You may like', padding: EdgeInsets.fromLTRB(20, 18, 20, 10))),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _mayLike.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _MiniCard(suggestion: _mayLike[i], onTap: () => _open(_mayLike[i])),
            ),
          ),
        ),
      ],
      if (_main.isNotEmpty)
        const SliverToBoxAdapter(child: SectionLabel('Best matches for you', padding: EdgeInsets.fromLTRB(20, 22, 20, 10))),
      if (_main.isNotEmpty)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 600,
            child: _top >= _main.length
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'You’ve gone through these suggestions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.muted),
                      ),
                    ),
                  )
                : CardSwiper(
                    key: ValueKey(_main),
                    controller: _swiper,
                    cardsCount: _main.length,
                    numberOfCardsDisplayed: _main.length - _top >= 2 ? 2 : 1,
                    isLoop: false,
                    initialIndex: _top.clamp(0, _main.length - 1),
                    duration: Motion.of(context, const Duration(milliseconds: 220)),
                    threshold: 35,
                    maxAngle: 12,
                    scale: 0.95,
                    backCardOffset: const Offset(0, 12),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    allowedSwipeDirection: const AllowedSwipeDirection.symmetric(horizontal: true),
                    onSwipe: _onSwipe,
                    cardBuilder: (context, index, dx, dy) {
                      final s = _main[index];
                      return SuggestionCard(suggestion: s, dragX: index == _top ? dx : 0, onTap: () => _open(s));
                    },
                  ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomBar + 24),
          child: Column(
            children: [
              if (status != null && status.remaining == 0)
                Text(
                  'You’ve seen today’s ${status.dailyLimit} suggestions. More tomorrow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                )
              else if (_main.length >= SuggestionsScreen.pageMax)
                PillButton(label: 'Next page', dark: false, height: 46, busy: _loadingMore, onTap: () => _more(nextPage: true))
              else if (_main.isNotEmpty)
                PillButton(label: 'Show more', dark: false, height: 46, busy: _loadingMore, onTap: _more),
              if (status != null && status.remaining > 0) ...[
                const SizedBox(height: 10),
                Text('${status.remaining} new suggestions left today', style: TextStyle(fontSize: 12.5, color: c.muted)),
              ],
            ],
          ),
        ),
      ),
    ];
  }
}

/// Full suggestion card: photo, name, age, short bio, district, the reasons
/// (shared interests, music, lifestyle) and a compatibility indicator.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({super.key, required this.suggestion, required this.onTap, this.dragX = 0});
  final Suggestion suggestion;
  final VoidCallback onTap;

  /// Horizontal drag (percent of the threshold, from the card swiper):
  /// right = request, left = pass. Shows the transparent ring icon.
  final int dragX;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final p = suggestion.profile;
    final reasons = suggestion.reasons.where((r) => r.kind != 'interests' && r.kind != 'music').take(2).toList();
    final progress = (dragX.abs() / 100).clamp(0.0, 1.0);
    final requesting = dragX > 0;
    final card = Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: SizedBox(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProfilePhoto(url: p.primaryPhoto, name: p.fullName),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.55, 1],
                            colors: [Color(0x000B0B0C), Color(0xE60B0B0C)],
                          ),
                        ),
                      ),
                      Positioned(top: 12, right: 12, child: CompatibilityBadge(value: suggestion.compatibility)),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(text: p.firstName),
                                        TextSpan(
                                          text: ' ${p.age}',
                                          style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFFC9C9CF)),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (p.isVerified) ...[const SizedBox(width: 8), const VerifiedBadge(size: 22)],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(PhosphorIconsFill.mapPin, size: 15, color: c.ink3),
                                const SizedBox(width: 5),
                                Text(
                                  p.city,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.bio.isNotEmpty) ...[
                  Text(
                    p.bio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, height: 1.4, color: c.ink2),
                  ),
                  const SizedBox(height: 10),
                ],
                if (suggestion.sharedInterests.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in suggestion.sharedInterests)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: c.accent.withValues(alpha: 0.6)),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFFF8A73)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (p.sharedArtists.isNotEmpty || p.topArtists.isNotEmpty) ...[
                  MusicAffinityTag(profile: p),
                  const SizedBox(height: 8),
                ],
                for (final r in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        VIcon(VIcons.done, size: 15, color: c.ok, stroke: 2.4),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(r.label, style: TextStyle(fontSize: 13.5, color: c.ink3)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (progress == 0) return card;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        card,
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, -0.45),
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
        ),
      ],
    );
  }
}

/// "88% match" ring.
class CompatibilityBadge extends StatelessWidget {
  const CompatibilityBadge({super.key, required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      label: '$value percent compatible',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(99)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 3,
                backgroundColor: Colors.white24,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '$value% match',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.suggestion, required this.onTap});
  final Suggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final p = suggestion.profile;
    final why = suggestion.reasons.isEmpty ? null : suggestion.reasons.first.label;
    return Pressable(
      scale: 0.97,
      onTap: onTap,
      semanticLabel: '${p.firstName}, ${p.age}. ${why ?? ''}',
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 150,
                height: 180,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProfilePhoto(url: p.primaryPhoto, name: p.fullName, decodeWidth: 360),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${suggestion.compatibility}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${p.firstName}, ${p.age}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
            ),
            if (why != null)
              Text(
                why,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.3, color: c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, required this.bottom, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(32, 0, 32, bottom + 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: c.muted),
          const SizedBox(height: 14),
          Text(title, style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.muted),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            PillButton(label: action!, dark: false, expand: false, height: 46, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      label: 'Loading suggestions',
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    Container(
                      width: 150,
                      height: 180,
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22)),
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              Container(
                height: 380,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(32)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
