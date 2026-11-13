import 'dart:io';
import 'dart:typed_data';

import 'package:finder_app/core/media_auth.dart';
import 'package:finder_app/core/media_cache.dart';
import 'package:finder_app/core/widgets.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id1 = '11111111-1111-4111-8111-111111111111';
const _id2 = '22222222-2222-4222-8222-222222222222';
const _base = 'https://x.supabase.co/functions/v1/media/';

void main() {
  late Directory tmp;
  late int calls;
  late List<Map<String, String>> sentHeaders;
  var status = 200;

  MediaDiskCache make({int maxBytes = 150 * 1024 * 1024}) {
    final client = MockClient((req) async {
      calls++;
      sentHeaders.add(req.headers);
      return http.Response.bytes(Uint8List.fromList(List.filled(1000, 7)), status);
    });
    return MediaDiskCache(baseDir: () async => tmp, client: client, maxBytes: maxBytes);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('vouby_media_test');
    calls = 0;
    sentHeaders = [];
    status = 200;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('first view downloads with the auth headers, later views come from disk', () async {
    final c = make();
    final h = {'Authorization': 'Bearer t'};
    final a = await c.get('$_base$_id1', scope: 'u1', headers: h);
    expect(a.length, 1000);
    expect(calls, 1);
    expect(sentHeaders.single['Authorization'], 'Bearer t');
    final again = await make().get('$_base$_id1', scope: 'u1', headers: h); // a new cache object = a new app launch
    expect(again.length, 1000);
    expect(calls, 1, reason: 'second launch reads the stored copy');
  });

  test('simultaneous requests for one photo share a single download', () async {
    final c = make();
    await Future.wait([for (var i = 0; i < 5; i++) c.get('$_base$_id1', scope: 'u1', headers: null)]);
    expect(calls, 1);
  });

  test('a failed download throws and stores nothing', () async {
    status = 404;
    final c = make();
    await expectLater(c.get('$_base$_id1', scope: 'u1', headers: null), throwsA(isA<HttpException>()));
    status = 200;
    await c.get('$_base$_id1', scope: 'u1', headers: null);
    expect(calls, 2, reason: 'nothing was cached from the failure');
  });

  test('copies are per account and never shared', () async {
    final c = make();
    await c.get('$_base$_id1', scope: 'u1', headers: null);
    await c.get('$_base$_id1', scope: 'u2', headers: null);
    expect(calls, 2);
  });

  test('without an account or a media id nothing is stored', () async {
    final c = make();
    await c.get('$_base$_id1', scope: null, headers: null);
    await c.get('$_base$_id1', scope: null, headers: null);
    await c.get('$_base-not-an-id', scope: 'u1', headers: null);
    expect(calls, 3);
  });

  test('clear removes one account only; trim drops the oldest first', () async {
    final c = make(maxBytes: 1500);
    await c.get('$_base$_id1', scope: 'u1', headers: null);
    await c.get('$_base$_id2', scope: 'u1', headers: null);
    await c.get('$_base$_id1', scope: 'u2', headers: null);
    final u1 = Directory('${tmp.path}/vouby_media/u1');
    File('${u1.path}/$_id1').setLastModifiedSync(DateTime(2020));
    await c.trim('u1');
    expect(File('${u1.path}/$_id1').existsSync(), isFalse, reason: 'oldest copy evicted');
    expect(File('${u1.path}/$_id2').existsSync(), isTrue);
    await c.clear('u1');
    expect(u1.existsSync(), isFalse);
    expect(Directory('${tmp.path}/vouby_media/u2').existsSync(), isTrue);
  });

  test('ProfilePhoto uses the disk-backed provider for media URLs only', () {
    MediaAuth.baseUrl = _base;
    addTearDown(() => MediaAuth.baseUrl = null);
    expect(ProfilePhoto.provider('$_base$_id1', 400), isA<ResizeImage>());
    final r = ProfilePhoto.provider('$_base$_id1', 400)! as ResizeImage;
    expect(r.imageProvider, isA<CachedMediaImage>());
    final other = ProfilePhoto.provider('https://example.com/a.png', 400)! as ResizeImage;
    expect(other.imageProvider, isA<NetworkImage>());
    expect(const CachedMediaImage('$_base$_id1'), const CachedMediaImage('$_base$_id1'));
  });
}
