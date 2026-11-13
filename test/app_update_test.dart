import 'dart:convert';

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/features/update/app_update.dart';
import 'package:finder_app/features/update/update_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _release(String tag, {String asset = 'finder-live-arm64.apk', String host = 'github.com'}) => {
  'tag_name': tag,
  'assets': [
    {'name': asset, 'browser_download_url': 'https://$host/fabooluxinterior/Finder_App/releases/download/$tag/$asset'},
  ],
};

void main() {
  group('release parsing', () {
    test('build tag and the live APK link', () {
      expect(buildFromTag('build-42'), 42);
      for (final bad in [null, '', 'v1.2', 'build-', 'build-x', 'build-1234567890', 'Build-5']) {
        expect(buildFromTag(bad), isNull, reason: '$bad');
      }
      final u = parseLatestRelease(_release('build-42'))!;
      expect(u.build, 42);
      expect(u.url.host, 'github.com');
    });

    test('anything unexpected is ignored', () {
      expect(parseLatestRelease(null), isNull);
      expect(parseLatestRelease('x'), isNull);
      expect(parseLatestRelease({'tag_name': 'build-3'}), isNull, reason: 'no assets');
      expect(parseLatestRelease(_release('build-3', asset: 'other.apk')), isNull, reason: 'wrong file');
      expect(parseLatestRelease(_release('build-3', host: 'evil.example')), isNull, reason: 'only github.com downloads');
      expect(parseLatestRelease({'tag_name': 7, 'assets': 'nope'}), isNull);
    });

    test('fetch: ok, errors and offline are all safe', () async {
      final ok = MockClient((_) async => http.Response(jsonEncode(_release('build-9')), 200));
      expect((await fetchLatestUpdate(client: ok))?.build, 9);
      expect(await fetchLatestUpdate(client: MockClient((_) async => http.Response('{}', 404))), isNull);
      expect(await fetchLatestUpdate(client: MockClient((_) async => http.Response('not json', 200))), isNull);
      expect(await fetchLatestUpdate(client: MockClient((_) async => throw Exception('offline'))), isNull);
    });
  });

  group('banner', () {
    Future<void> pump(WidgetTester t, {required bool supported, required int current, AppUpdate? latest}) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            updateSupportedProvider.overrideWithValue(supported),
            currentBuildProvider.overrideWithValue(current),
            latestUpdateFetcherProvider.overrideWithValue(() async => latest),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: const Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: UpdateBanner()),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }

    final newer = AppUpdate(build: 12, url: Uri.parse('https://github.com/x/y/releases/download/build-12/a.apk'));

    testWidgets('shows for a newer build, and Not now hides it', (t) async {
      await pump(t, supported: true, current: 10, latest: newer);
      expect(find.text('A new version is available'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      await t.tap(find.byTooltip('Not now'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('a build the user dismissed never comes back; a newer one does', (t) async {
      SharedPreferences.setMockInitialValues({'update_dismissed_build': 12});
      await pump(t, supported: true, current: 10, latest: newer);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A new version is available'), findsNothing);
      await t.pumpWidget(const SizedBox()); // a fresh start of the app
      SharedPreferences.setMockInitialValues({'update_dismissed_build': 11});
      await pump(t, supported: true, current: 10, latest: newer);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('A new version is available'), findsOneWidget);
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('stays hidden when up to date, offline, or on unsupported builds', (t) async {
      await pump(t, supported: true, current: 12, latest: newer);
      expect(find.text('A new version is available'), findsNothing, reason: 'same build');
      await pump(t, supported: true, current: 10, latest: null);
      expect(find.text('A new version is available'), findsNothing, reason: 'offline');
      await pump(t, supported: false, current: 10, latest: newer);
      expect(find.text('A new version is available'), findsNothing, reason: 'web/demo/local build');
    });
  });
}
