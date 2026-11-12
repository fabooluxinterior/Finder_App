import 'dart:async';
import 'dart:convert';

import '../models/message.dart';
import 'secure_kv.dart';

/// Decrypted conversation history kept only on this device, inside the
/// platform keystore-backed store. The server never holds plaintext.
class MessageVault {
  MessageVault(this._kv);
  final SecureKv _kv;
  static const _maxPerThread = 500;

  /// Every read-modify-write runs one after the other. Without this, a message arriving at the same moment
  /// as "mark as read" could write back its older copy and bring the unread count back.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await f());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  String _key(String me, String peer) => 'vault:$me:$peer';
  String _seenKey(String me) => 'vault:$me:_seen';

  Future<List<ChatMessage>> load(String me, String peer) async {
    final raw = await _kv.read(_key(me, peer));
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<ChatMessage>> upsert(String me, String peer, ChatMessage m) => _serial(() => _upsert(me, peer, m));

  Future<List<ChatMessage>> _upsert(String me, String peer, ChatMessage m) async {
    final list = await load(me, peer);
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final trimmed = list.length > _maxPerThread ? list.sublist(list.length - _maxPerThread) : list;
    await _kv.write(_key(me, peer), jsonEncode(trimmed.map((e) => e.toJson()).toList()));
    return trimmed;
  }

  Future<List<ChatMessage>> update(String me, String peer, ChatMessage Function(ChatMessage) f) =>
      _serial(() => _update(me, peer, f));

  Future<List<ChatMessage>> _update(String me, String peer, ChatMessage Function(ChatMessage) f) async {
    final list = (await load(me, peer)).map(f).toList();
    await _kv.write(_key(me, peer), jsonEncode(list.map((e) => e.toJson()).toList()));
    return list;
  }

  Future<void> deleteThread(String me, String peer) => _kv.delete(_key(me, peer));

  /// Client message ids already accepted (replay / duplicate guard).
  Future<bool> markSeen(String me, String senderId, String clientId) async {
    final raw = await _kv.read(_seenKey(me));
    final seen = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    final tag = '$senderId:$clientId';
    if (seen.contains(tag)) return false;
    seen.add(tag);
    await _kv.write(_seenKey(me), jsonEncode(seen.length > 5000 ? seen.sublist(seen.length - 5000) : seen));
    return true;
  }
}
