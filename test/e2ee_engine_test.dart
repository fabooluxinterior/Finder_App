import 'dart:convert';
import 'dart:io';

import 'package:finder_app/security/e2ee_engine.dart';
import 'package:finder_app/security/secure_kv.dart';
import 'package:finder_app/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the Supabase key directory (mirrors the RPC rules).
class FakeDirectory implements KeyDirectory {
  final devices = <String, RemoteDevice>{};
  final otks = <String, List<Map<String, Object?>>>{};
  final fallback = <String, Map<String, Object?>>{};
  final connected = <String>{};
  var tamperNextClaim = false;
  int _n = 0;

  bool _ok(String a, String b) => a == b || connected.contains(([a, b]..sort()).join());
  String? caller;

  @override
  Future<String> registerDevice({required String curve25519, required String ed25519, required String label, required String platform}) async {
    final existing = devices.values.where((d) => d.curve25519 == curve25519);
    if (existing.isNotEmpty) return existing.first.id;
    final id = 'dev${_n++}';
    devices[id] = RemoteDevice(id: id, userId: caller!, curve25519: curve25519, ed25519: ed25519);
    return id;
  }

  @override
  Future<int> uploadOneTimeKeys(String deviceId, List<Map<String, Object?>> keys) async {
    for (final k in keys) {
      if (k['fallback'] == true) {
        fallback[deviceId] = k;
      } else {
        (otks[deviceId] ??= []).add(k);
      }
    }
    return otks[deviceId]!.length;
  }

  @override
  Future<int> oneTimeKeyCount(String deviceId) async => otks[deviceId]?.length ?? 0;

  @override
  Future<List<RemoteDevice>> activeDevices(List<String> userIds) async =>
      devices.values.where((d) => userIds.contains(d.userId) && _ok(caller!, d.userId)).toList();

  @override
  Future<RemoteDevice?> deviceById(String deviceId) async => devices[deviceId];

  @override
  Future<List<ClaimedKey>> claimKeys(String userId, List<String> excludeDeviceIds) async {
    if (!_ok(caller!, userId)) throw StateError('Not connected');
    final out = <ClaimedKey>[];
    for (final d in devices.values.where((d) => d.userId == userId && !excludeDeviceIds.contains(d.id))) {
      final list = otks[d.id] ?? [];
      final k = list.isNotEmpty ? list.removeAt(0) : fallback[d.id];
      if (k == null) continue;
      var pk = k['public_key'] as String;
      if (tamperNextClaim) {
        // A malicious server swaps in a key it controls.
        pk = otks.values.expand((l) => l).first['public_key'] as String;
        tamperNextClaim = false;
      }
      out.add(ClaimedKey(device: d, keyId: k['key_id'] as String, publicKey: pk, signature: k['signature'] as String));
    }
    return out;
  }
}

void main() {
  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open('${Directory.current.path}/rust/target/debug/libfinder_crypto.so'));
  });

  test('alice <-> bob (two devices): fan-out, replies, replay & tamper rejection', () async {
    final dir = FakeDirectory()..connected.add((['alice', 'bob']..sort()).join());
    Future<E2eeEngine> engine(String user) async {
      dir.caller = user;
      final e = E2eeEngine(directory: dir, kv: MemorySecureKv(), platform: 'android');
      await e.ensureReady(user);
      return e;
    }

    final alice = await engine('alice');
    final bobPhone = await engine('bob');
    final bobTablet = await engine('bob');
    expect(dir.otks[bobPhone.deviceId]!.length, 50);

    dir.caller = 'alice';
    final env = await alice.encryptFor('bob', utf8.encode('hi bob'));
    expect(env.map((e) => e.deviceId).toSet(), {bobPhone.deviceId, bobTablet.deviceId});
    expect(env.every((e) => !e.ciphertext.contains('hi bob')), isTrue);

    dir.caller = 'bob';
    for (final (dev, eng) in [(bobPhone.deviceId, bobPhone), (bobTablet.deviceId, bobTablet)]) {
      final e = env.firstWhere((x) => x.deviceId == dev);
      expect(utf8.decode(await eng.decrypt(senderDeviceId: alice.deviceId, type: e.type, ciphertext: e.ciphertext)), 'hi bob');
      // Replay of the same envelope is rejected.
      await expectLater(eng.decrypt(senderDeviceId: alice.deviceId, type: e.type, ciphertext: e.ciphertext), throwsA(anything));
    }

    // Bob replies from his phone: goes to Alice and to Bob's tablet (own other device).
    final reply = await bobPhone.encryptFor('alice', utf8.encode('hey alice'));
    expect(reply.map((e) => e.deviceId).toSet(), {alice.deviceId, bobTablet.deviceId});
    dir.caller = 'alice';
    final toAlice = reply.firstWhere((e) => e.deviceId == alice.deviceId);
    expect(utf8.decode(await alice.decrypt(senderDeviceId: bobPhone.deviceId, type: toAlice.type, ciphertext: toAlice.ciphertext)), 'hey alice');
    dir.caller = 'bob';
    final toTablet = reply.firstWhere((e) => e.deviceId == bobTablet.deviceId);
    expect(utf8.decode(await bobTablet.decrypt(senderDeviceId: bobPhone.deviceId, type: toTablet.type, ciphertext: toTablet.ciphertext)), 'hey alice');

    // Ratchet continues; tampered ciphertext fails.
    dir.caller = 'alice';
    final m2 = (await alice.encryptFor('bob', utf8.encode('second'))).firstWhere((e) => e.deviceId == bobPhone.deviceId);
    expect(m2.type, 1);
    final raw = base64Decode(base64.normalize(m2.ciphertext + '=' * ((4 - m2.ciphertext.length % 4) % 4)));
    raw[raw.length ~/ 2] ^= 1;
    final bad = base64Encode(raw).replaceAll('=', '');
    dir.caller = 'bob';
    await expectLater(bobPhone.decrypt(senderDeviceId: alice.deviceId, type: 1, ciphertext: bad), throwsA(anything));
    expect(utf8.decode(await bobPhone.decrypt(senderDeviceId: alice.deviceId, type: 1, ciphertext: m2.ciphertext)), 'second');

    // Safety numbers match on both sides.
    dir.caller = 'alice';
    final sa = await alice.safetyNumber('bob');
    dir.caller = 'bob';
    expect(await bobPhone.safetyNumber('alice'), sa);
  });

  test('server-substituted one-time key is refused', () async {
    final dir = FakeDirectory()..connected.add((['carol', 'dave']..sort()).join());
    dir.caller = 'carol';
    final carol = E2eeEngine(directory: dir, kv: MemorySecureKv(), platform: 'web');
    await carol.ensureReady('carol');
    dir.caller = 'dave';
    final dave = E2eeEngine(directory: dir, kv: MemorySecureKv(), platform: 'android');
    await dave.ensureReady('dave');

    dir.caller = 'carol';
    dir.tamperNextClaim = true;
    await expectLater(carol.encryptFor('dave', utf8.encode('x')), throwsA(isA<E2eeException>()));
  });

  test('strangers cannot claim keys', () async {
    final dir = FakeDirectory();
    dir.caller = 'eve';
    final eve = E2eeEngine(directory: dir, kv: MemorySecureKv(), platform: 'android');
    await eve.ensureReady('eve');
    dir.caller = 'frank';
    await E2eeEngine(directory: dir, kv: MemorySecureKv(), platform: 'android').ensureReady('frank');
    dir.caller = 'eve';
    await expectLater(eve.encryptFor('frank', utf8.encode('x')), throwsA(anything));
  });

  test('attachments: AES-256-GCM roundtrip, wrong context rejected', () async {
    final b = await E2eeEngine.sealAttachment(utf8.encode('voice'), 'voice:1');
    expect(await E2eeEngine.openAttachment(key: b.key, nonce: b.nonce, ciphertext: b.ciphertext, sha256: b.sha256, aad: 'voice:1'), utf8.encode('voice'));
    await expectLater(E2eeEngine.openAttachment(key: b.key, nonce: b.nonce, ciphertext: b.ciphertext, sha256: b.sha256, aad: 'voice:2'), throwsA(anything));
  });
}
