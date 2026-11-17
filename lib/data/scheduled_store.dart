import 'dart:convert';
import 'dart:typed_data';

import '../models/scheduled_message.dart';
import '../security/secure_kv.dart';

/// Scheduled messages and their photos, in the phone's encrypted storage (wiped on sign-out with everything else).
class ScheduledStore {
  ScheduledStore(this._kv, this._uid);
  final SecureKv _kv;
  final String _uid;

  String get _listKey => 'vouby_scheduled_v1_$_uid';
  String _imgKey(String id) => 'vouby_scheduled_img_${_uid}_$id';

  Future<List<ScheduledMessage>> load() async {
    try {
      final raw = await _kv.read(_listKey);
      if (raw == null) return [];
      return [for (final j in (jsonDecode(raw) as List)) ScheduledMessage.fromJson((j as Map).cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ScheduledMessage> list) => _kv.write(_listKey, jsonEncode([for (final m in list) m.toJson()]));

  Future<void> putImage(String id, Uint8List bytes) => _kv.write(_imgKey(id), base64Encode(bytes));

  Future<Uint8List?> image(String id) async {
    final raw = await _kv.read(_imgKey(id));
    return raw == null ? null : base64Decode(raw);
  }

  Future<void> deleteImage(String id) => _kv.delete(_imgKey(id));
}
