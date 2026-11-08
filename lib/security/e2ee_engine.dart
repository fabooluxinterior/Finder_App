import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../src/rust/api/crypto.dart' as rc;
import 'secure_kv.dart';

/// A device's public identity as published on the server.
class RemoteDevice {
  const RemoteDevice({required this.id, required this.userId, required this.curve25519, required this.ed25519});
  final String id;
  final String userId;
  final String curve25519;
  final String ed25519;
}

class ClaimedKey {
  const ClaimedKey({required this.device, required this.keyId, required this.publicKey, required this.signature});
  final RemoteDevice device;
  final String keyId;
  final String publicKey;
  final String signature;
}

/// Server operations the engine needs. Implemented over Supabase RPCs; the
/// server only ever sees public keys and ciphertext.
abstract class KeyDirectory {
  Future<String> registerDevice({
    required String curve25519,
    required String ed25519,
    required String label,
    required String platform,
  });
  Future<int> uploadOneTimeKeys(String deviceId, List<Map<String, Object?>> keys);
  Future<int> oneTimeKeyCount(String deviceId);
  Future<List<RemoteDevice>> activeDevices(List<String> userIds);
  Future<RemoteDevice?> deviceById(String deviceId);
  Future<List<ClaimedKey>> claimKeys(String userId, List<String> excludeDeviceIds);
}

class Envelope {
  const Envelope({required this.deviceId, required this.type, required this.ciphertext});
  final String deviceId;
  final int type;
  final String ciphertext;
  Map<String, Object> toJson() => {'device_id': deviceId, 'type': type, 'ciphertext': ciphertext};
}

class E2eeException implements Exception {
  const E2eeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Per-device end-to-end encryption using Olm (Double Ratchet + 3DH) from
/// vodozemac, via the Rust core in /rust.
///
/// * Each install is a device with its own Curve25519/Ed25519 identity.
/// * Messages are encrypted separately for every active device of the
///   recipient and of the sender's other devices (multi-device fan-out).
/// * One-time keys are signed by the owning device and verified before use,
///   so the server can't substitute its own keys without detection of the
///   device identity itself (verify via safety numbers).
/// * All state (account + session pickles) is encrypted with a 256-bit
///   pickle key that lives only in the platform keystore.
class E2eeEngine {
  E2eeEngine({required this.directory, required this.kv, required this.platform, this.label = 'Device'});

  final KeyDirectory directory;
  final SecureKv kv;
  final String platform;
  final String label;

  static const _minOneTimeKeys = 20;
  static const _batch = 50;
  static const _maxSessionsPerDevice = 3;

  late Uint8List _pickleKey;
  late String _account;
  late String curve25519;
  late String ed25519;
  String? _deviceId;
  String? _userId;

  String get deviceId => _deviceId ?? (throw const E2eeException('Encryption not initialised'));

  // Serialises all ratchet operations: sessions must never be advanced concurrently.
  Future<void> _lock = Future.value();
  Future<T> _locked<T>(Future<T> Function() body) {
    final run = _lock.then((_) => body());
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  String _k(String name) => 'e2ee:$_userId:$name';

  /// Loads or creates this device's identity, registers it, and tops up
  /// one-time keys. Safe to call repeatedly.
  Future<void> ensureReady(String userId) => _locked(() async {
    if (_userId == userId && _deviceId != null) return;
    _userId = userId;
    final storedKey = await kv.read(_k('pickle_key'));
    if (storedKey == null) {
      _pickleKey = Uint8List.fromList(await rc.randomKey());
      await kv.write(_k('pickle_key'), base64Encode(_pickleKey));
    } else {
      _pickleKey = base64Decode(storedKey);
    }

    final stored = await kv.read(_k('account'));
    final ident = stored == null
        ? await rc.createDevice(pickleKey: _pickleKey)
        : await rc.deviceIdentity(accountPickle: stored, pickleKey: _pickleKey);
    _account = ident.accountPickle;
    curve25519 = ident.curve25519;
    ed25519 = ident.ed25519;
    await kv.write(_k('account'), _account);

    _deviceId = await directory.registerDevice(curve25519: curve25519, ed25519: ed25519, label: label, platform: platform);
    await kv.write(_k('device_id'), _deviceId!);
    await _replenishUnlocked();
  });

  Future<void> replenishOneTimeKeys() => _locked(_replenishUnlocked);

  Future<void> _replenishUnlocked() async {
    final count = await directory.oneTimeKeyCount(deviceId);
    if (count >= _minOneTimeKeys) return;
    final batch = await rc.generateOneTimeKeys(accountPickle: _account, pickleKey: _pickleKey, count: _batch);
    _account = batch.accountPickle;
    await kv.write(_k('account'), _account);
    await directory.uploadOneTimeKeys(deviceId, [
      for (final k in batch.keys) {'key_id': k.keyId, 'public_key': k.publicKey, 'signature': k.signature},
      if (batch.fallback != null)
        {
          'key_id': batch.fallback!.keyId,
          'public_key': batch.fallback!.publicKey,
          'signature': batch.fallback!.signature,
          'fallback': true,
        },
    ]);
  }

  // --------------------------------------------------------------- sessions

  Future<List<String>> _sessions(String theirCurve) async {
    final raw = await kv.read(_k('sess:$theirCurve'));
    return raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _saveSession(String theirCurve, String pickle, {String? replacing}) async {
    final list = await _sessions(theirCurve);
    if (replacing != null) list.remove(replacing);
    list.insert(0, pickle);
    await kv.write(_k('sess:$theirCurve'), jsonEncode(list.take(_maxSessionsPerDevice).toList()));
  }

  /// Encrypts [payload] for every active device of [peerUserId] and for
  /// this user's other devices. Returns one envelope per target device.
  Future<List<Envelope>> encryptFor(String peerUserId, Uint8List payload) => _locked(() async {
    final devices = (await directory.activeDevices([peerUserId, _userId!])).where((d) => d.id != deviceId).toList();
    if (!devices.any((d) => d.userId == peerUserId)) {
      throw const E2eeException('They need to open the app once before you can message them securely.');
    }

    // Establish sessions with devices we have none for, claiming their keys.
    final needing = <RemoteDevice>[];
    for (final d in devices) {
      if ((await _sessions(d.curve25519)).isEmpty) needing.add(d);
    }
    for (final owner in needing.map((d) => d.userId).toSet()) {
      final have = devices.where((d) => d.userId == owner && !needing.contains(d)).map((d) => d.id).toList();
      if (owner == _userId) have.add(deviceId);
      for (final claim in await directory.claimKeys(owner, have)) {
        final ok = await rc.verifyOneTimeKey(
          deviceEd25519: claim.device.ed25519,
          deviceCurve25519: claim.device.curve25519,
          otk: claim.publicKey,
          signature: claim.signature,
        );
        if (!ok) continue; // forged or corrupted key: never encrypt to it
        final pickle = await rc.createOutboundSession(
          accountPickle: _account,
          pickleKey: _pickleKey,
          theirCurve25519: claim.device.curve25519,
          theirOneTimeKey: claim.publicKey,
        );
        await _saveSession(claim.device.curve25519, pickle);
      }
    }

    final out = <Envelope>[];
    for (final d in devices) {
      final sessions = await _sessions(d.curve25519);
      if (sessions.isEmpty) continue;
      final m = await rc.encrypt(sessionPickle: sessions.first, pickleKey: _pickleKey, plaintext: payload);
      await _saveSession(d.curve25519, m.sessionPickle, replacing: sessions.first);
      out.add(Envelope(deviceId: d.id, type: m.messageType, ciphertext: m.ciphertext));
    }
    if (!out.any((e) => devices.firstWhere((d) => d.id == e.deviceId).userId == peerUserId)) {
      throw const E2eeException('Could not set up encryption with their device. Try again shortly.');
    }
    return out;
  });

  /// Decrypts an envelope addressed to this device. Throws on tampering,
  /// replay, or unknown sender device.
  Future<Uint8List> decrypt({required String senderDeviceId, required int type, required String ciphertext}) => _locked(() async {
    final sender = await directory.deviceById(senderDeviceId);
    if (sender == null) throw const E2eeException('Message from an unknown device');
    final sessions = await _sessions(sender.curve25519);

    for (final s in sessions) {
      if (type == 0 &&
          !await rc.sessionMatches(sessionPickle: s, pickleKey: _pickleKey, messageType: type, ciphertext: ciphertext)) {
        continue;
      }
      try {
        final r = await rc.decrypt(sessionPickle: s, pickleKey: _pickleKey, messageType: type, ciphertext: ciphertext);
        await _saveSession(sender.curve25519, r.sessionPickle, replacing: s);
        return r.plaintext;
      } catch (_) {
        if (type == 0) rethrow;
      }
    }
    if (type != 0) throw const E2eeException('Could not decrypt message');

    final r = await rc.decryptInbound(
      accountPickle: _account,
      pickleKey: _pickleKey,
      theirCurve25519: sender.curve25519,
      messageType: type,
      ciphertext: ciphertext,
    );
    _account = r.accountPickle!;
    await kv.write(_k('account'), _account);
    await _saveSession(sender.curve25519, r.sessionPickle);
    unawaited(_replenishUnlocked().catchError((_) {}));
    return r.plaintext;
  });

  /// 60-digit number both people can compare in person.
  Future<String> safetyNumber(String peerUserId) async {
    final devices = await directory.activeDevices([peerUserId, _userId!]);
    return rc.safetyNumber(
      myEd25519Keys: devices.where((d) => d.userId == _userId).map((d) => d.ed25519).toList(),
      theirEd25519Keys: devices.where((d) => d.userId == peerUserId).map((d) => d.ed25519).toList(),
    );
  }

  /// Wipes all local key material (sign-out / account deletion).
  Future<void> wipe() => _locked(() async {
    await kv.deleteAll();
    _deviceId = null;
    _userId = null;
  });

  // ------------------------------------------------------------- attachments

  static Future<rc.EncryptedBlob> sealAttachment(Uint8List bytes, String aad) =>
      rc.encryptBlob(plaintext: bytes, aad: utf8.encode(aad));

  static Future<Uint8List> openAttachment({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List sha256,
    required String aad,
  }) => rc.decryptBlob(key: key, nonce: nonce, ciphertext: ciphertext, sha256: sha256, aad: utf8.encode(aad));
}
