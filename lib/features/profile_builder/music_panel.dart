import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/spotify_logo.dart';
import '../../data/demo_backend.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../models/profile.dart';
import '../../providers.dart';

const spotifyGreen = Color(0xFF1ED760);

/// Connected-accounts module for Spotify: status switch, short explanation,
/// and five circular previews of your top artists ("+" when not connected).
/// Tapping the previews opens per-artist visibility controls.
class MusicPanel extends ConsumerStatefulWidget {
  const MusicPanel({super.key});

  @override
  ConsumerState<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends ConsumerState<MusicPanel> with WidgetsBindingObserver {
  bool _busy = false;
  bool _awaitingReturn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh the import if it's older than 12 h (the server decides; no
    // Spotify call happens otherwise).
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(force: false, quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the Spotify consent page in the browser.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturn) {
      _awaitingReturn = false;
      _reload();
    }
  }

  void _reload() {
    ref.invalidate(musicStateProvider);
    ref.invalidate(myProfileProvider);
  }

  Future<void> _sync({required bool force, bool quiet = false}) async {
    final music = await ref.read(musicStateProvider.future);
    if (!music.connected) return;
    final r = await ref.read(backendProvider).syncMusic(force: force);
    if (!mounted) return;
    if (r != MusicSyncResult.cached || force) _reload();
    if (!quiet && r == MusicSyncResult.cached && force) showSnack(context, 'Your artists are up to date.');
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final url = await ref.read(backendProvider).musicAuthorizeUrl();
      if (url.scheme == 'vouby-demo') {
        _reload(); // demo: already imported (from Spotify, or sample artists)
        final b = ref.read(backendProvider);
        if (mounted && b is DemoBackend && !b.realSpotify) {
          showSnack(context, 'Sample artists added. This build has no Spotify app ID set.');
        }
      } else {
        _awaitingReturn = true;
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Spotify?'),
        content: const Text(
          'Your artists are removed from your profile and we delete the access Spotify gave us. '
          'You can also remove Vouby under Apps in your Spotify account settings.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).disconnectMusic();
      _reload();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final music = ref.watch(musicStateProvider).value ?? MusicState.disconnected;
    final visible = music.artists.where((a) => a.visible).toList();
    final reauth = music.status == MusicStatus.reauthRequired;

    final subtitle = !music.connected
        ? 'Show your top artists on your profile and see who shares your taste.'
        : reauth
        ? 'Spotify access expired. Reconnect to keep your artists up to date.'
        : music.artists.isEmpty
        ? 'Connected. Listen a little more and your top artists will appear here.'
        : 'Your top ${visible.length} artists are on your profile. Tap to choose which ones show.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MusicServiceBadge(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spotify',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    Text(
                      reauth ? 'Needs reconnecting' : (music.connected ? 'Connected' : 'Not connected'),
                      style: TextStyle(fontSize: 13, color: reauth ? c.gold : (music.connected ? spotifyGreen : c.muted)),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Switch(
                  value: music.connected && !reauth,
                  activeTrackColor: spotifyGreen,
                  onChanged: (v) => v ? _connect() : _disconnect(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(subtitle, style: TextStyle(fontSize: 14, height: 1.4, color: c.ink3)),
          const SizedBox(height: 14),
          Semantics(
            button: music.artists.isNotEmpty,
            label: music.artists.isEmpty ? 'No artists yet' : 'Manage artist visibility',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: music.artists.isEmpty ? (music.connected ? null : _connect) : () => _manage(music),
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    i < visible.length ? ArtistAvatar(artist: visible[i], size: 52) : const _PlusCircle(size: 52),
                  ],
                ],
              ),
            ),
          ),
          if (music.connected && !reauth) ...[
            const SizedBox(height: 6),
            _SectionSwitch(
              title: 'Show most played',
              subtitle: music.topTracks.isEmpty ? 'Nothing yet' : '${music.topTracks.length} tracks',
              value: music.showTopTracks,
              onChanged: (v) => _setSection('top_tracks', v),
            ),
            _SectionSwitch(
              title: 'Show recently played',
              subtitle: !music.recentScope
                  ? 'Reconnect Spotify to add this'
                  : music.recentTracks.isEmpty
                  ? 'Nothing yet'
                  : 'Your last ${music.recentTracks.length} plays, with times',
              value: music.showRecent && music.recentScope,
              onChanged: music.recentScope ? (v) => _setSection('recent', v) : null,
            ),
            if (!music.recentScope)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _connect, child: const Text('Reconnect to show recently played')),
              ),
          ],
          if (reauth) ...[
            const SizedBox(height: 12),
            PillButton(label: 'Reconnect Spotify', height: 44, onTap: _connect),
          ] else if (music.connected && music.artists.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(onPressed: () => _manage(music), child: const Text('Choose visible artists')),
                const Spacer(),
                TextButton(onPressed: () => _sync(force: true), child: const Text('Refresh')),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _setSection(String section, bool visible) async {
    try {
      await ref.read(backendProvider).setMusicSectionVisibility(section, visible: visible);
      _reload();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _manage(MusicState music) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ArtistVisibilitySheet(),
  );
}

class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.ink),
              ),
              Text(subtitle, style: TextStyle(fontSize: 13, color: c.muted)),
            ],
          ),
        ),
        Switch(value: value, activeTrackColor: spotifyGreen, onChanged: onChanged),
      ],
    );
  }
}

class _ArtistVisibilitySheet extends ConsumerWidget {
  const _ArtistVisibilitySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final music = ref.watch(musicStateProvider).value ?? MusicState.disconnected;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          Text(
            'Your top artists',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Hidden artists never appear on your profile and are never used for matches.',
            style: TextStyle(fontSize: 14, height: 1.4, color: c.ink3),
          ),
          const SizedBox(height: 14),
          for (final a in music.artists)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Opacity(
                    opacity: a.visible ? 1 : 0.4,
                    child: ArtistAvatar(artist: a, size: 46),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
                        ),
                        if (a.genres.isNotEmpty)
                          Text(a.genres.take(2).join(' · '), style: TextStyle(fontSize: 13, color: c.muted)),
                      ],
                    ),
                  ),
                  Semantics(
                    label: '${a.visible ? 'Shown' : 'Hidden'}: ${a.name}',
                    child: Switch(
                      value: a.visible,
                      activeTrackColor: spotifyGreen,
                      onChanged: (v) async {
                        try {
                          await ref.read(backendProvider).setArtistVisibility(a.id, visible: v);
                          ref.invalidate(musicStateProvider);
                          ref.invalidate(myProfileProvider);
                        } on AppException catch (e) {
                          if (context.mounted) showSnack(context, e.message);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The Spotify logo beside the "Spotify" name in settings.
class MusicServiceBadge extends StatelessWidget {
  const MusicServiceBadge({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => SpotifyLogo(size: size);
}

class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.artist, this.size = 48, this.highlight = false});
  final MusicArtist artist;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // No photo from Spotify (or it failed to load): a visible person icon.
    final fallback = Container(
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: Icon(PhosphorIconsFill.user, size: size * 0.5, color: const Color(0xFFB3B3B3)),
    );
    return Semantics(
      label: artist.name,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(highlight ? 2 : 0),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: highlight ? Border.all(color: spotifyGreen, width: 2) : null,
        ),
        child: ClipOval(
          child: artist.image == null
              ? fallback
              : Image.network(
                  artist.image!,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _PlusCircle extends StatelessWidget {
  const _PlusCircle({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.paper,
        border: Border.all(color: c.hair),
      ),
      child: Icon(Icons.add, color: c.muted, size: size * 0.4),
    );
  }
}
