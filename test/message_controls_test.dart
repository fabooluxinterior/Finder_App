import 'dart:typed_data';

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/core/feedback.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chat/chat_screen.dart' show isSingleEmoji;
import 'package:finder_app/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

Future<(DemoBackend, String)> _chat() async {
  final b = DemoBackend();
  await b.verifyOtp(OtpChannel.email, 'asha@example.com', '123456');
  await b.setDob(DateTime(1998, 3, 3));
  await b.acknowledgeStandards('2026-11-11');
  await b.createProfile(
    fullName: 'Asha Menon',
    city: 'Kochi',
    details: const ProfilePatch({
      ProfilePatch.gender: 'woman',
      ProfilePatch.bio: 'Filter coffee and long walks by the sea.',
      ProfilePatch.prefGenders: ['man'],
      ProfilePatch.interestTags: ['Hiking', 'Chess', 'Poetry', 'Baking', 'Cycling'],
      ProfilePatch.prompts: [
        {'prompt_id': 'p1', 'answer': 'Evening chai at Fort Kochi'},
        {'prompt_id': 'p4', 'answer': 'Sunrise, appam, nap'},
      ],
    }),
  );
  for (var i = 0; i < 4; i++) {
    await b.uploadPhoto(_bytes(1000 + i), mime: 'image/webp');
  }
  await b.completeOnboarding();
  return (b, (await b.connections()).first.profile.id);
}

void main() {
  group('edit and delete payloads', () {
    test('an edit round-trips and tells older apps something readable', () {
      final p = SecurePayload(clientId: 'c1', sentAt: DateTime.utc(2026, 11, 12), editTarget: 'm1', text: 'new words');
      final back = SecurePayload.decode(p.encode());
      expect(back.isControl, isTrue);
      expect((back.editTarget, back.text, back.deleteTarget), ('m1', 'new words', null));
    });

    test('a delete round-trips and carries no text', () {
      final p = SecurePayload(clientId: 'c2', sentAt: DateTime.utc(2026, 11, 12), deleteTarget: 'm1');
      final back = SecurePayload.decode(p.encode());
      expect((back.deleteTarget, back.text, back.editTarget), ('m1', null, null));
    });

    test('a normal message is not a control message', () {
      final back = SecurePayload.decode(SecurePayload(clientId: 'c3', sentAt: DateTime.utc(2026), text: 'hi').encode());
      expect((back.isControl, back.text), (false, 'hi'));
    });

    test('edited and deleted flags survive storage; a deleted message keeps nothing', () {
      final m = ChatMessage(
        id: 'a',
        senderId: 'x',
        receiverId: 'y',
        content: 'secret',
        isRead: true,
        createdAt: DateTime.utc(2026),
      );
      final e = ChatMessage.fromJson(m.withEditedText('fixed').toJson());
      expect((e.content, e.edited, e.deleted), ('fixed', true, false));
      final d = ChatMessage.fromJson(m.asDeleted().toJson());
      expect((d.content, d.deleted, d.isVoice, d.isImage), (null, true, false, false));
    });
  });

  group('editing and deleting in a chat', () {
    test('edit changes the text and marks it edited; empty text is refused', () async {
      final (b, peer) = await _chat();
      await b.sendText(peer, 'Hi thre');
      final sent = (await b.watchMessages(peer).first).lastWhere((m) => m.senderId == b.currentUserId);
      await b.editMessage(peer, sent.id, 'Hi there');
      final after = (await b.watchMessages(peer).first).firstWhere((m) => m.id == sent.id);
      expect((after.content, after.edited), ('Hi there', true));
      await expectLater(b.editMessage(peer, sent.id, '   '), throwsA(isA<AppException>()));
    });

    test('delete leaves a placeholder, then nothing more can be done to it', () async {
      final (b, peer) = await _chat();
      await b.sendText(peer, 'Oops wrong chat');
      final sent = (await b.watchMessages(peer).first).lastWhere((m) => m.senderId == b.currentUserId);
      await b.deleteMessage(peer, sent.id);
      final after = (await b.watchMessages(peer).first).firstWhere((m) => m.id == sent.id);
      expect((after.deleted, after.content), (true, null));
      expect((await b.connections()).first.lastMessage, isNot('Oops wrong chat'));
      await expectLater(b.deleteMessage(peer, sent.id), throwsA(isA<AppException>()));
      await expectLater(b.editMessage(peer, sent.id, 'again'), throwsA(isA<AppException>()));
    });

    test('someone else’s message cannot be edited or deleted', () async {
      final (b, peer) = await _chat();
      final theirs = (await b.watchMessages(peer).first).firstWhere((m) => m.senderId == peer);
      await expectLater(b.deleteMessage(peer, theirs.id), throwsA(isA<AppException>()));
      await expectLater(b.editMessage(peer, theirs.id, 'hacked'), throwsA(isA<AppException>()));
    });
  });

  test('the receive sound plays once for a burst of notices about the same message', () {
    // Two calls within 1.5 s are one sound; this only checks the guard does not throw or loop.
    Fx.instance.received();
    Fx.instance.received();
  });

  group('disappearing messages', () {
    ChatMessage msg(DateTime at) => ChatMessage(
      id: '${at.millisecondsSinceEpoch}',
      senderId: 'a',
      receiverId: 'b',
      content: 'hi',
      isRead: true,
      createdAt: at,
    );

    test('only messages sent after turning it on can expire, and only after the chosen time', () {
      final now = DateTime(2026, 11, 17, 12);
      final d = Disappearing(seconds: 86400, setBy: 'a', setAt: now.subtract(const Duration(days: 3)));
      expect(d.expired(msg(now.subtract(const Duration(days: 10))), now), isFalse, reason: 'sent before it was turned on');
      expect(d.expired(msg(now.subtract(const Duration(days: 2))), now), isTrue);
      expect(d.expired(msg(now.subtract(const Duration(hours: 23))), now), isFalse);
      expect(Disappearing.off.expired(msg(now.subtract(const Duration(days: 99))), now), isFalse);
      expect([for (final s in Disappearing.choices) Disappearing.label(s)], ['24 hours', '7 days', '1 month']);
    });

    test('demo: either choice is stored, invalid ones are refused, and turning off keeps everything', () async {
      final (b, peer) = await _chat();
      expect((await b.disappearing(peer)).on, isFalse);
      await expectLater(b.setDisappearing(peer, 3600), throwsA(isA<AppException>()));
      await b.setDisappearing(peer, 604800);
      expect((await b.disappearing(peer)).seconds, 604800);
      await b.sendText(peer, 'hello');
      await b.purgeExpired(peer);
      expect((await b.watchMessages(peer).first).any((m) => m.content == 'hello'), isTrue, reason: 'not expired yet');
      await b.setDisappearing(peer, 0);
      expect((await b.disappearing(peer)).on, isFalse);
    });
  });

  group('receipts and emoji', () {
    test('one grey tick = sent, two grey = delivered, two blue = read', () {
      final t = DateTime(2026, 11, 17, 12);
      ChatMessage m({DateTime? d, DateTime? r, bool read = false}) => ChatMessage(
        id: 'x',
        senderId: 'a',
        receiverId: 'b',
        content: 'hi',
        isRead: read,
        createdAt: t,
        deliveredAt: d,
        readAt: r,
      );
      expect(m().receipt, ReceiptStatus.sent);
      expect(m(d: t).receipt, ReceiptStatus.delivered);
      expect(m(d: t, r: t).receipt, ReceiptStatus.read);
      expect(m(read: true).receipt, ReceiptStatus.read, reason: 'older apps only set is_read');
    });

    test('receipt times survive the on-device copy', () {
      final t = DateTime.utc(2026, 11, 17, 12);
      final m = ChatMessage(
        id: 'x',
        senderId: 'a',
        receiverId: 'b',
        content: 'hi',
        isRead: true,
        createdAt: t,
        deliveredAt: t.add(const Duration(seconds: 2)),
        readAt: t.add(const Duration(minutes: 5)),
        listenedAt: t.add(const Duration(minutes: 6)),
      );
      final back = ChatMessage.fromJson(m.toJson());
      expect(
        (back.deliveredAt, back.readAt, back.listenedAt),
        (m.deliveredAt!.toLocal(), m.readAt!.toLocal(), m.listenedAt!.toLocal()),
      );
    });
  });

  test('only a single emoji on its own is shown larger', () {
    for (final e in ['😀', '❤️', '👍🏽', '🇮🇳', '👨‍👩‍👧', '🙏']) {
      expect(isSingleEmoji(e), isTrue, reason: e);
    }
    for (final e in ['😀😀', 'hi 😀', 'a', '', '1', '😀 ok']) {
      expect(isSingleEmoji(e), isFalse, reason: e);
    }
    expect(isSingleEmoji(null), isFalse);
  });
}
