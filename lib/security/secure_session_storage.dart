import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_kv.dart';

/// Keeps the Supabase session (access + refresh token) in the platform
/// keystore instead of plain SharedPreferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this._kv);
  final SecureKv _kv;
  static const _key = 'sb_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _kv.read(_key)) != null;

  @override
  Future<String?> accessToken() => _kv.read(_key);

  @override
  Future<void> persistSession(String persistSessionString) => _kv.write(_key, persistSessionString);

  @override
  Future<void> removePersistedSession() => _kv.delete(_key);
}
