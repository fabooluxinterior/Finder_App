import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../models/profile.dart';

/// Opens the consent page and returns the full redirect URL.
typedef SpotifyAuthenticator = Future<String> Function(Uri url, String callbackScheme);

/// Tokens from Spotify's Authorization Code + PKCE flow. PKCE needs only the
/// public client ID, so no client secret is ever shipped in the app.
class SpotifyTokens {
  const SpotifyTokens({required this.access, required this.refresh, required this.expiresAt, required this.scope});
  final String access;
  final String refresh;
  final DateTime expiresAt;
  final String scope;

  bool get expired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));
  bool get hasRecentScope => scope.split(' ').contains('user-read-recently-played');
}

class SpotifyImport {
  const SpotifyImport({required this.artists, required this.tracks, required this.recent});
  final List<MusicArtist> artists;
  final List<MusicTrack> tracks;

  /// Null when the recently-played scope wasn't granted.
  final List<MusicTrack>? recent;
}

/// Thrown when Spotify no longer accepts the saved refresh token
/// (access removed in the Spotify account, or the token expired).
class SpotifyReauthRequired implements Exception {
  const SpotifyReauthRequired();
}

/// Talks to Spotify straight from the app. Used by demo builds, which have
/// no server; production builds go through the music-* edge functions.
class SpotifyDirect {
  SpotifyDirect({required this.clientId, http.Client? client, SpotifyAuthenticator? authenticate, Random? random})
    : _http = client ?? http.Client(),
      _authenticate = authenticate ?? _webAuth,
      _rand = random ?? Random.secure();

  /// Public client ID from the Spotify developer dashboard, set at build time
  /// with --dart-define=SPOTIFY_CLIENT_ID=... (not a secret).
  static const envClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static bool get configured => envClientId.isNotEmpty;

  static const scopes = 'user-top-read user-read-recently-played';
  static const callbackScheme = 'vouby-spotify';
  static const _accounts = 'https://accounts.spotify.com';
  static const _api = 'https://api.spotify.com/v1';
  static final _id = RegExp(r'^[A-Za-z0-9]{10,40}$');

  final String clientId;
  final http.Client _http;
  final SpotifyAuthenticator _authenticate;
  final Random _rand;

  /// Must be listed exactly under Redirect URIs in the Spotify dashboard.
  /// Web: the spotify_callback.html page next to the app; Android/iOS: the
  /// vouby-spotify://callback link.
  static String get redirectUri => kIsWeb ? Uri.base.resolve('spotify_callback.html').toString() : '$callbackScheme://callback';

  static Future<String> _webAuth(Uri url, String scheme) => FlutterWebAuth2.authenticate(
    url: url.toString(),
    callbackUrlScheme: scheme,
    options: const FlutterWebAuth2Options(windowName: '_blank'),
  );

  String _random(int n) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(n, (_) => chars[_rand.nextInt(chars.length)]).join();
  }

  static String challengeFor(String verifier) =>
      base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  /// Runs the consent flow and returns tokens. Throws [AppException] when
  /// the person cancels or Spotify refuses.
  Future<SpotifyTokens> connect() async {
    final verifier = _random(64);
    final state = _random(24);
    final url = Uri.parse('$_accounts/authorize').replace(
      queryParameters: {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirectUri,
        'scope': scopes,
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': challengeFor(verifier),
      },
    );
    final String result;
    try {
      result = await _authenticate(url, callbackScheme);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw const AppException(AppErrorCode.invalidInput, 'Spotify sign-in was cancelled.');
      throw AppException(AppErrorCode.network, 'Couldn’t open Spotify sign-in (${e.code}).');
    }
    final back = Uri.parse(result).queryParameters;
    if (back['state'] != state) throw const AppException(AppErrorCode.unknown, 'Spotify sign-in didn’t match. Try again.');
    if (back['error'] != null) {
      throw AppException(
        AppErrorCode.invalidInput,
        back['error'] == 'access_denied' ? 'You didn’t allow access on Spotify.' : 'Spotify said: ${back['error']}',
      );
    }
    final code = back['code'];
    if (code == null || code.isEmpty) throw const AppException(AppErrorCode.unknown, 'Spotify didn’t return a code.');
    return _token({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': verifier,
    });
  }

  Future<SpotifyTokens> refresh(SpotifyTokens old) async {
    try {
      return await _token({'grant_type': 'refresh_token', 'refresh_token': old.refresh, 'client_id': clientId}, old);
    } on _BadGrant {
      throw const SpotifyReauthRequired();
    }
  }

  Future<SpotifyTokens> _token(Map<String, String> body, [SpotifyTokens? old]) async {
    final http.Response res;
    try {
      res = await _http.post(
        Uri.parse('$_accounts/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
    } catch (_) {
      throw const AppException(AppErrorCode.network, 'Couldn’t reach Spotify. Check your connection.');
    }
    if (res.statusCode == 400 && res.body.contains('invalid_grant')) throw const _BadGrant();
    if (res.statusCode != 200) {
      var why = '';
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        why = '${j['error'] ?? ''}${j['error_description'] != null ? ': ${j['error_description']}' : ''}';
      } catch (_) {}
      throw AppException(AppErrorCode.unknown, 'Spotify sign-in failed (${res.statusCode}${why.isEmpty ? '' : ', $why'}).');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return SpotifyTokens(
      access: j['access_token'] as String,
      // Spotify may or may not rotate the refresh token.
      refresh: (j['refresh_token'] as String?) ?? old?.refresh ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600)),
      scope: (j['scope'] as String?) ?? old?.scope ?? '',
    );
  }

  Future<Map<String, dynamic>?> _get(String access, String path, {bool optional = false}) async {
    final http.Response res;
    try {
      res = await _http.get(Uri.parse('$_api$path'), headers: {'Authorization': 'Bearer $access'});
    } catch (_) {
      throw const AppException(AppErrorCode.network, 'Couldn’t reach Spotify. Check your connection.');
    }
    if (res.statusCode == 401) throw const SpotifyReauthRequired();
    if (res.statusCode == 403 && optional) return null; // scope not granted
    if (res.statusCode == 403) {
      throw const AppException(
        AppErrorCode.unknown,
        'Spotify refused access. While the Vouby Spotify app is in development mode, '
        'your Spotify account must be added under User Management in the Spotify dashboard.',
      );
    }
    if (res.statusCode != 200) throw AppException(AppErrorCode.unknown, 'Spotify error (${res.statusCode}).');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String? _pick(Object? images, int want) {
    final list = [
      for (final i in (images as List? ?? const []).cast<Map<String, dynamic>>())
        if (i['url'] is String && (i['url'] as String).startsWith('https://')) i,
    ];
    if (list.isEmpty) return null;
    num gap(Map<String, dynamic> i) => (((i['width'] as num?) ?? want) - want).abs();
    list.sort((a, b) => gap(a).compareTo(gap(b)));
    return list.first['url'] as String;
  }

  static List<MusicArtist> mapArtists(Object? items) => [
    for (final a in (items as List? ?? const []).cast<Map<String, dynamic>>().take(10))
      if (a['id'] is String && _id.hasMatch(a['id'] as String) && a['name'] is String && (a['name'] as String).isNotEmpty)
        MusicArtist(
          id: a['id'] as String,
          name: (a['name'] as String).length > 80 ? (a['name'] as String).substring(0, 80) : a['name'] as String,
          image: _pick(a['images'], 320),
          genres: [
            for (final g in (a['genres'] as List? ?? const []).take(5))
              if (g is String) g,
          ],
        ),
  ];

  static MusicTrack? mapTrack(Object? t, {int? rank, DateTime? playedAt}) {
    if (t is! Map<String, dynamic>) return null;
    final id = t['id'], name = t['name'];
    if (id is! String || !_id.hasMatch(id) || name is! String || name.isEmpty) return null;
    return MusicTrack(
      id: id,
      name: name.length > 100 ? name.substring(0, 100) : name,
      artists: [
        for (final a in (t['artists'] as List? ?? const []).take(3))
          if (a is Map && a['name'] is String) a['name'] as String,
      ],
      image: _pick((t['album'] as Map?)?['images'], 300),
      rank: rank,
      playedAt: playedAt,
    );
  }

  /// Top artists and tracks (~6 months) and the last plays.
  Future<SpotifyImport> importAll(String access) async {
    final results = await Future.wait([
      _get(access, '/me/top/artists?limit=10&time_range=medium_term'),
      _get(access, '/me/top/tracks?limit=10&time_range=medium_term'),
      _get(access, '/me/player/recently-played?limit=10', optional: true),
    ]);
    final tracks = <MusicTrack>[];
    for (final t in (results[1]?['items'] as List? ?? const [])) {
      final m = mapTrack(t, rank: tracks.length + 1);
      if (m != null) tracks.add(m);
    }
    List<MusicTrack>? recent;
    if (results[2] != null) {
      recent = [];
      for (final it in (results[2]!['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final m = mapTrack(it['track'], playedAt: DateTime.tryParse(it['played_at'] as String? ?? ''));
        if (m == null) continue;
        // The same song played twice in a row shows once.
        if (recent.isNotEmpty && recent.last.id == m.id) continue;
        recent.add(m);
        if (recent.length == 5) break;
      }
    }
    return SpotifyImport(artists: mapArtists(results[0]?['items']), tracks: tracks, recent: recent);
  }
}

class _BadGrant implements Exception {
  const _BadGrant();
}
