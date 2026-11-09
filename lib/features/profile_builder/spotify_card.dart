import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/phosphor.dart';
import '../../core/spotify_logo.dart';

import '../../models/profile.dart';

/// Black-theme palette for the Spotify card (approved layout: logo + heading,
/// artist pills with round photos, dividers between sections).
class _P {
  static const card = Color(0xFF121212);
  static const border = Color(0xFF262626);
  static const pill = Color(0xFF242424);
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color(0xFFB3B3B3);
  static const muted = Color(0xFF8A8A8A);
  static const line = Color(0xFF2A2A2A);
  static const sharedPill = Color(0x241ED760);
  static const sharedRing = Color(0xFF1ED760);
  static const placeholder = Color(0xFF2E2E2E);
}

/// Opens an artist or track in the Spotify app (or web player). Demo items
/// have no real Spotify page, so they don't link anywhere.
Future<void> openOnSpotify(String kind, String id) async {
  if (id.startsWith('demo')) return;
  await launchUrl(Uri.parse('https://open.spotify.com/$kind/$id'), mode: LaunchMode.externalApplication);
}

/// The music part of a profile, in this order: Spotify heading, top artists
/// (pills), most played (Spotify's ranking with artwork, five then "See all")
/// and recently played (latest five with times). Everything comes from the
/// stored import; opening a profile never calls Spotify.
class SpotifyProfileCard extends StatefulWidget {
  const SpotifyProfileCard({super.key, required this.profile});
  final PublicProfile profile;

  static bool hasContent(PublicProfile p) => p.topArtists.isNotEmpty || p.topTracks.isNotEmpty || p.recentTracks.isNotEmpty;

  @override
  State<SpotifyProfileCard> createState() => _SpotifyProfileCardState();
}

class _SpotifyProfileCardState extends State<SpotifyProfileCard> {
  bool _allTracks = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final shared = p.sharedArtistIds.toSet();
    final sharedArtists = p.sharedArtists;
    final tracks = _allTracks ? p.topTracks : p.topTracks.take(5).toList();
    final onlyArtists = p.topTracks.isEmpty && p.recentTracks.isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: _P.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _P.border),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Geist', color: _P.ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SpotifyLogo(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    onlyArtists ? 'My top artists on Spotify' : 'My music on Spotify',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: _P.ink),
                  ),
                ),
              ],
            ),
            if (sharedArtists.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
                decoration: BoxDecoration(color: _P.sharedPill, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SpotifyLogo(size: 16, semanticLabel: null),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'You both listen to ${sharedArtists.first.name}'
                        '${sharedArtists.length > 1 ? ' +${sharedArtists.length - 1}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _P.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (p.topArtists.isNotEmpty) ...[
              if (!onlyArtists) const _Heading('Top artists') else const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final a in p.topArtists) _ArtistPill(artist: a, shared: shared.contains(a.id))],
              ),
            ],

            if (p.topTracks.isNotEmpty) ...[
              const _Divider(),
              const _Heading('Most played', note: 'Spotify’s ranking, last 6 months'),
              for (final t in tracks) _TrackRow(track: t, leading: (t.rank ?? 0).toString().padLeft(2, '0')),
              if (p.topTracks.length > 5)
                TextButton(
                  onPressed: () => setState(() => _allTracks = !_allTracks),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: _P.ink2,
                    minimumSize: const Size(44, 40),
                  ),
                  child: Text(
                    _allTracks ? 'Show less' : 'See all ${p.topTracks.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
            ],

            if (p.recentTracks.isNotEmpty) ...[
              const _Divider(),
              const _Heading('Recently played'),
              for (final t in p.recentTracks.take(5))
                _TrackRow(track: t, trailing: t.playedAt == null ? null : timeAgo(t.playedAt!)),
            ],
            const _Divider(),
            const SizedBox(height: 10),
            const Row(
              children: [
                SpotifyLogo(size: 14, color: _P.muted, semanticLabel: null),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Details from Spotify. Tap an artist or track to open it there.',
                    style: TextStyle(fontSize: 12, color: _P.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(height: 1, margin: const EdgeInsets.only(top: 16), color: _P.line);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.note});
  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _P.ink),
        ),
        if (note != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              note!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _P.muted),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Circular artist photo + name in a light-grey rounded pill.
class _ArtistPill extends StatelessWidget {
  const _ArtistPill({required this.artist, required this.shared});
  final MusicArtist artist;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${artist.name}${shared ? ', you both listen' : ''}',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => openOnSpotify('artist', artist.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 16, 3),
          decoration: BoxDecoration(
            color: shared ? _P.sharedPill : _P.pill,
            borderRadius: BorderRadius.circular(999),
            border: shared ? Border.all(color: _P.sharedRing, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundImage(url: artist.image, size: 38, label: artist.name),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  artist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _P.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundImage extends StatelessWidget {
  const _RoundImage({required this.url, required this.size, required this.label});
  final String? url;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    // No photo from Spotify: a visible person icon.
    final fallback = Container(
      color: _P.placeholder,
      alignment: Alignment.center,
      child: Icon(PhosphorIconsFill.user, size: size * 0.52, color: _P.ink2),
    );
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: url == null
            ? fallback
            : Image.network(url!, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// Compact row: optional rank, square artwork, title, artist, optional time.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, this.leading, this.trailing});
  final MusicTrack track;
  final String? leading;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${leading != null ? 'Number ${int.tryParse(leading!) ?? leading}: ' : ''}${track.name} by ${track.artistLine}'
          '${trailing != null ? ', $trailing' : ''}',
      button: true,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => openOnSpotify('track', track.id),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              if (leading != null)
                SizedBox(
                  width: 28,
                  child: Text(
                    leading!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _P.muted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Artwork(url: track.image, size: 46),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _P.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artistLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, color: _P.ink2),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Text(trailing!, style: const TextStyle(fontSize: 12.5, color: _P.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    // No album art from Spotify: a visible music icon.
    final fallback = Container(
      width: size,
      height: size,
      color: _P.placeholder,
      child: Icon(PhosphorIconsFill.musicNotes, size: size * 0.48, color: _P.ink2),
    );
    if (url == null) return fallback;
    return Image.network(
      url!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// "10 min ago", "3 h ago", "yesterday", "4 days ago", "12 Oct".
String timeAgo(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]}';
}
