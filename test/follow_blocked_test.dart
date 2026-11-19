import 'dart:typed_data';

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chats/chats_screen.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

Future<DemoBackend> _user() async {
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
  return b;
}

void main() {
  group('followers and following', () {
    test('every connection has a direction, and the lists are separate', () async {
      final b = await _user();
      final all = await b.connections();
      expect(all, isNotEmpty);
      for (final c in all) {
        expect(c.iFollow || c.followsMe, isTrue);
      }
      expect(all.where((c) => c.followsMe).length + all.where((c) => c.iFollow).length, greaterThanOrEqualTo(all.length));
    });

    test('a chat appears only once somebody has written', () async {
      final b = await _user();
      final all = await b.connections();
      final quiet = all.where((c) => !c.hasChat).toList();
      if (quiet.isEmpty) return;
      final before = all.where((c) => c.hasChat).length;
      await b.sendText(quiet.first.profile.id, 'Hello!');
      final after = (await b.connections()).where((c) => c.hasChat).length;
      expect(after, before + 1);
    });
  });

  group('blocked users', () {
    test('blocking lists the person, unblocking removes them and does not restore the connection', () async {
      final b = await _user();
      final first = (await b.connections()).first;
      expect(await b.blockedUsers(), isEmpty);
      await b.blockUser(first.profile.id);
      final blocked = await b.blockedUsers();
      expect(blocked.map((u) => u.id), [first.profile.id]);
      expect((await b.connections()).map((c) => c.profile.id), isNot(contains(first.profile.id)));
      await b.unblock(first.profile.id);
      expect(await b.blockedUsers(), isEmpty);
      expect((await b.connections()).map((c) => c.profile.id), isNot(contains(first.profile.id)));
    });
  });

  testWidgets('Chats lists only messaged people; the search icon stretches open and finds the rest', (tester) async {
    final (b, all) = (await tester.runAsync(() async {
      final u = await _user();
      // Accept a request: a new connection with nobody having written yet.
      final reqs = (await u.incomingRequests()).requests;
      if (reqs.isNotEmpty) await u.respondToRequest(reqs.first.id, accept: true);
      return (u, await u.connections());
    }))!;
    final quiet = all.where((c) => !c.hasChat).toList();
    final chatted = all.where((c) => c.hasChat).toList();
    expect(quiet, isNotEmpty);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(b)],
        child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ChatsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    // People without a chat are not listed.
    expect(find.text(quiet.first.profile.firstName), findsNothing);
    if (chatted.isNotEmpty) expect(find.text(chatted.first.profile.firstName), findsWidgets);
    // Search icon opens the bar, and typing finds someone with no chat.
    await tester.tap(find.byTooltip('Search people you follow'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), quiet.first.profile.firstName.substring(0, 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(quiet.first.profile.firstName), findsWidgets);
  });
}
