import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/e2ee_engine.dart';

class SupabaseKeyDirectory implements KeyDirectory {
  SupabaseKeyDirectory(this._db);
  final SupabaseClient _db;

  RemoteDevice _device(Map<String, dynamic> r) => RemoteDevice(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        curve25519: r['curve25519'] as String,
        ed25519: r['ed25519'] as String,
      );

  @override
  Future<String> registerDevice({required String curve25519, required String ed25519, required String label, required String platform}) async =>
      await _db.rpc('register_device', params: {
        'p_curve25519': curve25519,
        'p_ed25519': ed25519,
        'p_label': label,
        'p_platform': platform,
      }) as String;

  @override
  Future<int> uploadOneTimeKeys(String deviceId, List<Map<String, Object?>> keys) async =>
      (await _db.rpc('upload_one_time_keys', params: {'p_device': deviceId, 'p_keys': keys}) as num).toInt();

  @override
  Future<int> oneTimeKeyCount(String deviceId) async =>
      (await _db.rpc('one_time_key_count', params: {'p_device': deviceId}) as num).toInt();

  @override
  Future<List<RemoteDevice>> activeDevices(List<String> userIds) async {
    final rows = await _db
        .from('devices')
        .select('id, user_id, curve25519, ed25519')
        .inFilter('user_id', userIds)
        .isFilter('revoked_at', null);
    return rows.map(_device).toList();
  }

  @override
  Future<RemoteDevice?> deviceById(String deviceId) async {
    final r = await _db.from('devices').select('id, user_id, curve25519, ed25519').eq('id', deviceId).maybeSingle();
    return r == null ? null : _device(r);
  }

  @override
  Future<List<ClaimedKey>> claimKeys(String userId, List<String> excludeDeviceIds) async {
    final rows = await _db.rpc('claim_device_keys', params: {'p_user': userId, 'p_exclude': excludeDeviceIds}) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        ClaimedKey(
          device: RemoteDevice(
            id: r['device_id'] as String,
            userId: userId,
            curve25519: r['curve25519'] as String,
            ed25519: r['ed25519'] as String,
          ),
          keyId: r['key_id'] as String,
          publicKey: r['public_key'] as String,
          signature: r['signature'] as String,
        ),
    ];
  }
}
