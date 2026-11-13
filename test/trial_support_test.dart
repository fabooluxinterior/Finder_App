import 'dart:convert';
import 'dart:typed_data';

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/help/faq_content.dart';
import 'package:finder_app/features/help/help_center_screen.dart';
import 'package:finder_app/features/paywall/paywall_sheet.dart' show perDayFromLabel;
import 'package:finder_app/models/access.dart';
import 'package:finder_app/models/message.dart';
import 'package:finder_app/models/moderation.dart';
import 'package:finder_app/models/security.dart';
import 'package:finder_app/models/support.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

/// A new demo account that has just finished setup.
Future<DemoBackend> _newUser() async {
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
  return b;
}

void main() {
  group('7-day trial', () {
    test('starts when setup finishes, exactly 168 hours, unlocks chat', () async {
      final b = await _newUser();
      expect((await b.accessStatus()).plan, AccessPlan.free);
      await b.completeOnboarding();
      final a = await b.accessStatus();
      expect(a.plan, AccessPlan.trial);
      expect(a.trialEndsAt!.difference(a.trialStartedAt!), const Duration(hours: 168));
      expect(a.daysLeft(DateTime.now()), 7);
      expect(await b.serverPremium(), isTrue);
      expect((await b.notifications()).first.kind, 'trial_started');
    });

    test('24-hour reminder, expiry keeps chats, subscribing restores', () async {
      final b = await _newUser();
      await b.completeOnboarding();
      final peer = (await b.connections()).first.profile.id;
      await b.sendText(peer, 'Hi there!');

      b.debugShiftTrial(const Duration(hours: 150));
      expect((await b.accessStatus()).notice, 'trial_24h');
      await b.markAccessNoticeSeen('trial_24h');
      expect((await b.accessStatus()).notice, isNull);

      b.debugShiftTrial(const Duration(hours: 169));
      final ended = await b.accessStatus();
      expect((ended.plan, ended.notice), (AccessPlan.free, 'trial_ended'));
      await expectLater(
        b.sendText(peer, 'Still there?'),
        throwsA(isA<AppException>().having((e) => e.code, 'code', AppErrorCode.subscriptionRequired)),
      );
      final kept = await b.watchMessages(peer).first;
      expect(kept.any((m) => m.content == 'Hi there!'), isTrue, reason: 'chat history is never deleted');

      b.setPremium(true);
      expect((await b.accessStatus()).plan, AccessPlan.fastTrack);
      await b.sendText(peer, 'Back!');
    });

    test('price per day is shown only when exact', () {
      expect(perDayPrice(), '₹2.63');
      expect(perDayFromLabel('₹79'), '₹2.63');
      expect(perDayFromLabel('₹1,499'), '₹49.97');
      expect(perDayFromLabel('US\$4.99'), isNull);
      expect(perDayFromLabel('₹79.00 / mo'), isNull);
    });
  });

  group('support tickets', () {
    test('validation, ticket number, history, status updates, daily limit', () async {
      final b = await _newUser();
      expect(validateTicket(subject: 'Hi', description: 'Something is wrong'), isNotNull);
      expect(validateTicket(subject: 'Payment', description: 'short'), isNotNull);
      final t = await b.submitSupportTicket(
        category: SupportCategory.subscription,
        subject: 'Trial question',
        description: 'When does my free trial end exactly?',
      );
      expect(t.ticketNo, matches(RegExp(r'^VB-[2-9A-Z]{6}$')));
      expect(t.email, 'asha@example.com');
      expect(t.status, TicketStatus.newTicket);
      expect((await b.myTickets()).single.id, t.id);

      for (var i = 0; i < 4; i++) {
        await b.submitSupportTicket(category: SupportCategory.other, subject: 'Ticket $i', description: 'Testing the limit');
      }
      await expectLater(
        b.submitSupportTicket(category: SupportCategory.other, subject: 'Too many', description: 'Testing the limit'),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('reports and chat photos', () {
    test('photo messages: sent to a connection, opened on device, not to strangers', () async {
      final b = await _newUser();
      await b.completeOnboarding();
      final peer = (await b.connections()).first.profile.id;
      final photo = _bytes(5000);
      await b.sendImage(peer, photo, width: 800, height: 1000);
      final m = (await b.watchMessages(peer).first).lastWhere((m) => m.isImage);
      expect(await b.imageBytes(m), photo);
      final stranger = (await b.fetchFeed()).first.id;
      await expectLater(b.sendImage(stranger, photo, width: 1, height: 1), throwsA(isA<AppException>()));
    });

    test('report with selected evidence gets a number', () async {
      final b = await _newUser();
      await b.completeOnboarding();
      final peer = (await b.connections()).first.profile.id;
      final no = await b.reportWithEvidence(
        peer,
        ReportReason.impersonation,
        details: 'Uses someone else’s photos',
        contentRef: 'msg:1',
        evidence: const ReportEvidence(
          texts: [
            {'message_id': '1', 'text': 'hello'},
          ],
        ),
        block: false,
      );
      expect(no, matches(RegExp(r'^R-[2-9A-Z]{6}$')));
    });

    test('report categories match the server list', () {
      final wires = ReportReason.values.where((r) => r.selectable).map((r) => r.wire).toSet();
      expect(
        wires,
        containsAll([
          'fake_profile',
          'harassment',
          'abusive_messages',
          'inappropriate_images',
          'spam',
          'scam',
          'impersonation',
          'suspicious_behaviour',
          'other',
        ]),
      );
    });

    test('photo payload: new apps see the photo, older apps see a hint', () {
      final p = SecurePayload(
        clientId: 'c1',
        sentAt: DateTime.utc(2026, 11, 11),
        image: ImageRef(
          path: 'a_b/c1.bin',
          key: Uint8List(32),
          nonce: Uint8List(12),
          sha256: Uint8List(32),
          width: 800,
          height: 1000,
        ),
      );
      final bytes = p.encode();
      expect((jsonDecode(utf8.decode(bytes)) as Map)['text'], photoFallbackText, reason: 'what an older app shows');
      final back = SecurePayload.decode(bytes);
      expect((back.text, back.image!.path, back.image!.width), (null, 'a_b/c1.bin', 800));
    });
  });

  group('help center', () {
    test('six categories, each with answers', () {
      expect(faqCategories.map((c) => c.title), [
        'Account and profile',
        'Discovery and matching',
        'Chat and messaging',
        'Subscription and payments',
        'Privacy and security',
        'Safety and reporting',
      ]);
      expect(faqCategories.every((c) => c.items.length >= 3), isTrue);
    });

    testWidgets('pick a topic, then a question, and the answer appears', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(DemoBackend())],
          child: MaterialApp(theme: buildTheme(Brightness.dark), home: const HelpCenterScreen()),
        ),
      );
      expect(find.text('Still need help? Contact support'), findsOneWidget);
      await tester.tap(find.text('Subscription and payments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('What is the 7-day free trial?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('168 hours'), findsOneWidget);
    });
  });
}
