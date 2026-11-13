import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'media_auth.dart';

/// On-device copy of photos fetched from the authorised media function.
///
/// A photo's URL ends in its media id and a media id never changes (replacing a photo creates a new id), so a
/// stored copy is always the right bytes. Every download still goes through the same authorised request as
/// before; this only avoids repeating it. Copies live in the app's private cache folder, one folder per signed-in
/// account, are trimmed to a size limit (oldest first) and are removed on sign-out.
class MediaDiskCache {
  MediaDiskCache({Future<Directory> Function()? baseDir, http.Client? client, this.maxBytes = 150 * 1024 * 1024})
    : _baseDir = baseDir ?? getApplicationCacheDirectory,
      _http = client ?? http.Client();

  static final instance = MediaDiskCache();

  final Future<Directory> Function() _baseDir;
  final http.Client _http;
  final int maxBytes;
  final _inFlight = <String, Future<Uint8List>>{};
  var _writes = 0;

  static final _id = RegExp(r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$');

  Future<Directory> _dir(String scope) async {
    final base = await _baseDir();
    final d = Directory('${base.path}/vouby_media/${scope.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// The photo's bytes: from disk when present, otherwise downloaded (with the caller's auth headers) and stored.
  Future<Uint8List> get(String url, {required String? scope, required Map<String, String>? headers}) {
    final id = _id.firstMatch(Uri.parse(url).path)?.group(1);
    if (scope == null || scope.isEmpty || id == null) return _download(url, headers);
    final key = '$scope/$id';
    return _inFlight[key] ??= _fetch(url, scope, id, headers).whenComplete(() {
      _inFlight.remove(key); // statement body: returning the removed future would make it wait on itself
    });
  }

  Future<Uint8List> _download(String url, Map<String, String>? headers) async {
    final res = await _http.get(Uri.parse(url), headers: headers);
    if (res.statusCode != 200) throw HttpException('Image request failed (${res.statusCode})', uri: Uri.parse(url));
    if (res.bodyBytes.isEmpty) throw HttpException('Empty image', uri: Uri.parse(url));
    return res.bodyBytes;
  }

  Future<Uint8List> _fetch(String url, String scope, String id, Map<String, String>? headers) async {
    File? file;
    try {
      file = File('${(await _dir(scope)).path}/$id');
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          unawaited(file.setLastModified(DateTime.now()).catchError((_) => file!)); // most recently used
          return bytes;
        }
      }
    } catch (_) {
      /* unreadable cache: fall back to the network */
    }
    final bytes = await _download(url, headers);
    try {
      final f = file ?? File('${(await _dir(scope)).path}/$id');
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      if (++_writes % 20 == 0) unawaited(trim(scope));
    } catch (_) {
      /* disk full or read-only: the photo still shows */
    }
    return bytes;
  }

  /// Deletes the oldest copies until the folder is under the limit.
  Future<void> trim(String scope) async {
    try {
      final files = [
        for (final e in (await _dir(scope)).listSync())
          if (e is File && !e.path.endsWith('.part')) e,
      ];
      var total = files.fold<int>(0, (s, f) => s + f.lengthSync());
      if (total <= maxBytes) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in files) {
        if (total <= maxBytes * 0.8) break;
        total -= f.lengthSync();
        f.deleteSync();
      }
    } catch (_) {}
  }

  /// Removes everything stored for one account (sign-out, account deletion).
  Future<void> clear(String? scope) async {
    try {
      final base = Directory('${(await _baseDir()).path}/vouby_media');
      if (!base.existsSync()) return;
      if (scope == null) {
        base.deleteSync(recursive: true);
      } else {
        final d = Directory('${base.path}/${scope.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}');
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}

/// Drop-in for NetworkImage on authorised media URLs: same request, same headers, same errors, but the bytes are
/// kept on disk so later launches and re-opened screens don't download and decrypt the photo again.
@immutable
class CachedMediaImage extends ImageProvider<CachedMediaImage> {
  const CachedMediaImage(this.url, {this.cache});
  final String url;
  final MediaDiskCache? cache;

  /// Mobile only; the web build keeps using the browser's own cache.
  static bool get supported => !kIsWeb;

  @override
  Future<CachedMediaImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<CachedMediaImage>(this);

  @override
  ImageStreamCompleter loadImage(CachedMediaImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1.0, debugLabel: key.url);

  Future<ui.Codec> _load(CachedMediaImage key, ImageDecoderCallback decode) async {
    final bytes = await (cache ?? MediaDiskCache.instance).get(
      key.url,
      scope: MediaAuth.scope?.call(),
      headers: MediaAuth.headers?.call(),
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is CachedMediaImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
