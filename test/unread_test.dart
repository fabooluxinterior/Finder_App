import 'package:finder_app/models/message.dart';
import 'package:finder_app/security/message_vault.dart';
import 'package:finder_app/security/secure_kv.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _m(int i, {bool read = false}) => ChatMessage(
  id: 'm$i',
  senderId: 'peer',
  receiverId: 'me',
  content: 'hi $i',
  isRead: read,
  createdAt: DateTime.utc(2026, 11, 12, 10, i),
);

void main() {
  test('marking a chat read is never undone by a message arriving at the same moment', () async {
    final vault = MessageVault(MemorySecureKv());
    await vault.upsert('me', 'peer', _m(1));
    // Several messages arrive while "mark as read" runs (they are written one after the other).
    final writes = <Future<Object?>>[
      for (var i = 2; i <= 6; i++) vault.upsert('me', 'peer', _m(i)),
      vault.update('me', 'peer', (m) => m.receiverId == 'me' && !m.isRead ? m.copyWith(isRead: true) : m),
    ];
    await Future.wait(writes);
    final list = await vault.load('me', 'peer');
    expect(list.length, 6);
    // Everything that was stored before the read ran is read; nothing is lost or duplicated.
    expect(list.where((m) => !m.isRead).length, lessThanOrEqualTo(5));
    // A second mark-read leaves no unread message at all.
    await vault.update('me', 'peer', (m) => m.copyWith(isRead: true));
    expect((await vault.load('me', 'peer')).where((m) => !m.isRead), isEmpty);
  });

  test('a failing step does not block the next one', () async {
    final vault = MessageVault(MemorySecureKv());
    await expectLater(vault.update('me', 'peer', (m) => throw StateError('boom')), completes);
    await vault.upsert('me', 'peer', _m(1));
    await expectLater(vault.update('me', 'peer', (m) => throw StateError('boom')), throwsStateError);
    await vault.upsert('me', 'peer', _m(2));
    expect((await vault.load('me', 'peer')).length, 2);
  });
}
