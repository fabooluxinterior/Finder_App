import 'dart:convert';

import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/data/spotify_direct.dart';
import 'package:finder_app/models/profile.dart';
import 'package:finder_app/security/secure_kv.dart';
import 'package:finder_app/core/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _artist = {
  'id': '0TnOYISbd1XYRBk9myaseg',
  'name': 'Real Artist',
  'genres': ['indie'],
  'images': [
    {'url': 'https://i.scdn.co/image/big', 'width': 640},
    {'url': 'https://i.scdn.co/image/mid', 'width': 320},
  ],
};

Map<String, Object> _track(String id, String name) => {
  'id': id,
  'name': name,
  'artists': [
    {'name': 'Real Artist'},
  ],
  'album': {
    'images': [
      {'url': 'https://i.scdn.co/image/art', 'width': 300},
    ],
  },
};

void main() {
  late List<http.Request> calls;
  late Uri authUrl;
  var recentStatus = 200;
  var tokenGrant = 'ok';

  MockClient client() => MockClient((req) async {
    calls.add(req);
    final p = req.url.path;
    if (p == '/api/token') {
      if (tokenGrant == 'bad') return http.Response('{"error":"invalid_grant"}', 400);
      return http.Response(
        jsonEncode({
          'access_token': 'acc-${calls.length}',
          'refresh_token': 'ref',
          'expires_in': 3600,
          'scope': recentStatus == 200 ? 'user-top-read user-read-recently-played' : 'user-top-read',
        }),
        200,
      );
    }
    if (p.endsWith('/me/top/artists')) {
      return http.Response(
        jsonEncode({
          'items': [
            _artist,
            {'id': 'bad id!', 'name': 'x'},
          ],
        }),
        200,
      );
    }
    if (p.endsWith('/me/top/tracks')) {
      return http.Response(
        jsonEncode({
          'items': [_track('4uLU6hMCjMI75M1A2tKUQC', 'Song A'), _track('7ouMYWpwJ422jRcDASZB7P', 'Song B')],
        }),
        200,
      );
    }
    if (p.endsWith('/me/player/recently-played')) {
      if (recentStatus != 200) return http.Response('', recentStatus);
      return http.Response(
        jsonEncode({
          'items': [
            {'track': _track('4uLU6hMCjMI75M1A2tKUQC', 'Song A'), 'played_at': '2026-11-09T04:50:00Z'},
            {'track': _track('4uLU6hMCjMI75M1A2tKUQC', 'Song A'), 'played_at': '2026-11-09T04:46:00Z'},
            {'track': _track('7ouMYWpwJ422jRcDASZB7P', 'Song B'), 'played_at': '2026-11-09T04:40:00Z'},
          ],
        }),
        200,
      );
    }
    return http.Response('', 404);
  });

  SpotifyDirect direct({String Function(Uri url)? redirect}) => SpotifyDirect(
    clientId: 'publicClientId',
    client: client(),
    authenticate: (url, scheme) async {
      authUrl = url;
      expect(scheme, 'vouby-spotify');
      final state = url.queryParameters['state'];
      return redirect?.call(url) ?? 'vouby-spotify://callback?code=abc&state=$state';
    },
  );

  setUp(() {
    calls = [];
    recentStatus = 200;
    tokenGrant = 'ok';
  });

  test('PKCE consent: S256 challenge, no secret, code exchanged with the verifier', () async {
    final t = await direct().connect();
    expect(authUrl.queryParameters['code_challenge_method'], 'S256');
    expect(authUrl.queryParameters['scope'], 'user-top-read user-read-recently-played');
    expect(authUrl.queryParameters['redirect_uri'], 'vouby-spotify://callback');
    final body = calls.single.bodyFields;
    expect(body['client_id'], 'publicClientId');
    expect(body.containsKey('client_secret'), isFalse);
    expect(SpotifyDirect.challengeFor(body['code_verifier']!), authUrl.queryParameters['code_challenge']);
    expect(t.access, isNotEmpty);
    expect(t.hasRecentScope, isTrue);
  });

  test('a redirect with the wrong state or a denial is refused', () async {
    await expectLater(
      direct(redirect: (_) => 'vouby-spotify://callback?code=abc&state=forged').connect(),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      direct(redirect: (u) => 'vouby-spotify://callback?error=access_denied&state=${u.queryParameters['state']}').connect(),
      throwsA(isA<AppException>().having((e) => e.message, 'message', contains('didn’t allow'))),
    );
    expect(calls, isEmpty); // nothing exchanged
  });

  test('import maps real artists, ranked tracks and de-duplicated recent plays', () async {
    final data = await direct().importAll('token');
    expect(data.artists.single.name, 'Real Artist');
    expect(data.artists.single.image, 'https://i.scdn.co/image/mid');
    expect(data.tracks.map((t) => (t.name, t.rank)), [('Song A', 1), ('Song B', 2)]);
    expect(data.tracks.first.image, 'https://i.scdn.co/image/art');
    expect(data.recent!.map((t) => t.name), ['Song A', 'Song B']);
    expect(data.recent!.first.playedAt, DateTime.utc(2026, 11, 9, 4, 50));
  });

  test('missing recently-played scope keeps the rest', () async {
    recentStatus = 403;
    final data = await direct().importAll('token');
    expect(data.recent, isNull);
    expect(data.tracks, hasLength(2));
  });

  test('demo backend connects a real account, refreshes, and asks to reconnect on a revoked token', () async {
    final kv = MemorySecureKv();
    final b = DemoBackend(spotify: direct(), secrets: kv);
    expect(b.realSpotify, isTrue);
    await b.musicAuthorizeUrl();
    var m = await b.musicState();
    expect(m.status, MusicStatus.active);
    expect(m.artists.single.id, '0TnOYISbd1XYRBk9myaseg');
    expect(m.topTracks, hasLength(2));
    expect(kv.map.keys, contains('vouby_demo_spotify_tokens'));

    expect(await b.syncMusic(), MusicSyncResult.cached); // synced < 1 h ago
    expect(await b.syncMusic(force: true), MusicSyncResult.synced);

    // Expired access + revoked refresh token -> reconnect.
    final saved = jsonDecode(kv.map['vouby_demo_spotify_tokens']!) as Map<String, dynamic>;
    kv.map['vouby_demo_spotify_tokens'] = jsonEncode({...saved, 'e': '2000-01-01T00:00:00.000'});
    tokenGrant = 'bad';
    expect(await b.syncMusic(force: true), MusicSyncResult.reauthRequired);
    m = await b.musicState();
    expect(m.status, MusicStatus.reauthRequired);

    await b.disconnectMusic();
    expect(kv.map, isEmpty);
  });

  test('without a client ID the demo falls back to sample artists', () async {
    final b = DemoBackend();
    expect(b.realSpotify, isFalse);
    await b.musicAuthorizeUrl();
    expect((await b.musicState()).artists, isNotEmpty);
  });
}
