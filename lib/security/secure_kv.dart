import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key-value store for secrets and encrypted state.
abstract class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Android: values encrypted with a key held in the Android Keystore
/// (hardware-backed where available). iOS: Keychain, this-device-only.
/// Web: the browser has no hardware keystore; values are AES-GCM encrypted
/// with a WebCrypto key kept in the same origin's storage. That protects
/// against casual inspection but not against XSS or a compromised browser
/// profile — see SECURITY.md.
class PlatformSecureKv implements SecureKv {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    webOptions: WebOptions(dbName: 'finder_secure', publicKey: 'finder'),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

@visibleForTesting
class MemorySecureKv implements SecureKv {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);

  @override
  Future<void> deleteAll() async => map.clear();
}
