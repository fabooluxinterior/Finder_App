import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import 'music_panel.dart' show ArtistAvatar, spotifyGreen;

/// Pick favorite artists and songs by searching, without logging in to Spotify. Up to 10 of each.
class MusicPickerSheet extends ConsumerStatefulWidget {
  const MusicPickerSheet({super.key});

  @override
  ConsumerState<MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends ConsumerState<MusicPickerSheet> {
  static const _max = 10;
  final _q = TextEditingController();
  Timer? _debounce;
  var _result = const MusicSearchResult();
  final _artists = <MusicArtist>[];
  final _tracks = <MusicTrack>[];
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = ref.read(musicStateProvider).value;
    if (m != null) {
      _artists.addAll(m.artists);
      _tracks.addAll(m.topTracks);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    if (v.trim().length < 2) {
      setState(() {
        _result = const MusicSearchResult();
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await ref.read(backendProvider).searchMusic(v);
      if (!mounted || _q.text != v) return;
      setState(() {
        _result = r;
        _error = null;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _toggleArtist(MusicArtist a) => setState(() {
    final i = _artists.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      _artists.removeAt(i);
    } else if (_artists.length < _max) {
      _artists.add(a);
    } else {
      showSnack(context, 'You can pick up to $_max artists.');
    }
  });

  void _toggleTrack(MusicTrack t) => setState(() {
    final i = _tracks.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _tracks.removeAt(i);
    } else if (_tracks.length < _max) {
      _tracks.add(t);
    } else {
      showSnack(context, 'You can pick up to $_max songs.');
    }
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(backendProvider).saveMusicPicks(artists: _artists, tracks: _tracks);
      ref.invalidate(musicStateProvider);
      ref.invalidate(myProfileProvider);
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pick your favorites',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Search artists and songs. No Spotify login needed. Up to $_max of each.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.ink3),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _q,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search artists or songs',
                      prefixIcon: Icon(Icons.search_rounded, color: c.muted),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  if (_error != null) Text(_error!, style: TextStyle(color: c.muted)),
                  if (_artists.isNotEmpty || _tracks.isNotEmpty) ...[
                    _Heading('Your picks (${_artists.length} artists, ${_tracks.length} songs)'),
                    for (final a in _artists) _ArtistRow(artist: a, picked: true, onTap: () => _toggleArtist(a)),
                    for (final t in _tracks) _TrackRow(track: t, picked: true, onTap: () => _toggleTrack(t)),
                  ],
                  if (_result.artists.isNotEmpty) ...[
                    const _Heading('Artists'),
                    for (final a in _result.artists)
                      _ArtistRow(artist: a, picked: _artists.any((x) => x.id == a.id), onTap: () => _toggleArtist(a)),
                  ],
                  if (_result.tracks.isNotEmpty) ...[
                    const _Heading('Songs'),
                    for (final t in _result.tracks)
                      _TrackRow(track: t, picked: _tracks.any((x) => x.id == t.id), onTap: () => _toggleTrack(t)),
                  ],
                  if (_q.text.trim().length >= 2 &&
                      !_searching &&
                      _error == null &&
                      _result.artists.isEmpty &&
                      _result.tracks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('No results.', style: TextStyle(color: c.muted)),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: PillButton(
                  label: _saving ? 'Saving…' : 'Save',
                  height: 48,
                  onTap: _saving || (_artists.isEmpty && _tracks.isEmpty) ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.fc.muted),
    ),
  );
}

class _PickMark extends StatelessWidget {
  const _PickMark(this.picked);
  final bool picked;
  @override
  Widget build(BuildContext context) =>
      Icon(picked ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.plus, color: picked ? spotifyGreen : context.fc.muted);
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist, required this.picked, required this.onTap});
  final MusicArtist artist;
  final bool picked;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ArtistAvatar(artist: artist, size: 44),
      title: Text(
        artist.name,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
      ),
      subtitle: artist.genres.isEmpty ? null : Text(artist.genres.take(2).join(' · '), style: TextStyle(color: c.muted)),
      trailing: _PickMark(picked),
      onTap: onTap,
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.picked, required this.onTap});
  final MusicTrack track;
  final bool picked;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(PhosphorIconsFill.musicNotes, color: c.ink3),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
      ),
      subtitle: Text(
        track.artistLine,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.muted),
      ),
      trailing: _PickMark(picked),
      onTap: onTap,
    );
  }
}
