import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';

/// A newer build published on GitHub Releases.
class AppUpdate {
  const AppUpdate({required this.build, required this.url});
  final int build;
  final Uri url;
}

/// "build-123" -> 123; anything else -> null.
int? buildFromTag(String? tag) {
  final m = RegExp(r'^build-(\d{1,9})$').firstMatch(tag ?? '');
  return m == null ? null : int.parse(m.group(1)!);
}

/// Reads GitHub's "latest release" answer. Only an https github.com download
/// of the live APK is accepted; anything else is ignored.
AppUpdate? parseLatestRelease(Object? json, {String asset = 'finder-live-arm64.apk'}) {
  if (json is! Map) return null;
  final tag = json['tag_name'];
  final build = buildFromTag(tag is String ? tag : null);
  if (build == null) return null;
  for (final a in (json['assets'] as List? ?? const [])) {
    if (a is Map && a['name'] == asset) {
      final u = Uri.tryParse(a['browser_download_url'] is String ? a['browser_download_url'] as String : '');
      if (u != null && u.scheme == 'https' && u.host == 'github.com') return AppUpdate(build: build, url: u);
    }
  }
  return null;
}

/// Asks GitHub for the newest published build. Any failure is silent (null).
Future<AppUpdate?> fetchLatestUpdate({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(
          Uri.https('api.github.com', '/repos/${AppConfig.updateRepo}/releases/latest'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    return parseLatestRelease(jsonDecode(res.body));
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Only real Android builds made by CI (they know their build number) check.
final updateSupportedProvider = Provider<bool>((ref) => !kIsWeb && !AppConfig.isDemo && AppConfig.buildNumber > 0);
final currentBuildProvider = Provider<int>((ref) => AppConfig.buildNumber);

/// Overridable in tests.
final latestUpdateFetcherProvider = Provider<Future<AppUpdate?> Function()>((ref) => fetchLatestUpdate);

/// The newer build, or null when up to date, unsupported or offline.
final availableUpdateProvider = FutureProvider<AppUpdate?>((ref) async {
  if (!ref.watch(updateSupportedProvider)) return null;
  final latest = await ref.watch(latestUpdateFetcherProvider)();
  return latest != null && latest.build > ref.watch(currentBuildProvider) ? latest : null;
});
