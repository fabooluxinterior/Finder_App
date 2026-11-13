import 'dart:typed_data';

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/data/purchases_service.dart';
import 'package:finder_app/features/chat/chat_screen.dart';
import 'package:finder_app/features/chats/chats_screen.dart';
import 'package:finder_app/features/help/contact_support_screen.dart';
import 'package:finder_app/features/profile/blocked_users_screen.dart';
import 'package:finder_app/features/profile/follow_lists_screen.dart';
import 'package:finder_app/features/profile/my_profile_screen.dart';
import 'package:finder_app/features/suggestions/suggestion_carousel.dart';
import 'package:finder_app/models/follow_request.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

/// A finished demo account with the sample people, one accepted request (a connection with no chat yet)
/// and a message written to the first person in the chat list.
Future<(DemoBackend, List<Connection>)> _world() async {
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
  final reqs = (await b.incomingRequests()).requests;
  if (reqs.isNotEmpty) await b.respondToRequest(reqs.first.id, accept: true);
  return (b, await b.connections());
}

Widget _app(DemoBackend b, Widget home) => ProviderScope(
  overrides: [backendProvider.overrideWithValue(b), purchasesProvider.overrideWithValue(DemoPurchases(b))],
  child: MaterialApp(theme: buildTheme(Brightness.dark), home: home),
);

Future<void> _settle(WidgetTester t, [int ms = 600]) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pump(Duration(milliseconds: ms));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('You: People and Blocked open their screens; no duplicate followers cards, settings icon or Bio card', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const MyProfileScreen()));
    await _settle(t);
    // Removed: the two followers cards, the settings icon at the top right and the Bio card.
    expect(find.text('Only you can see these numbers and lists'), findsNothing);
    expect(find.bySemanticsLabel('Privacy & security'), findsNothing);
    expect(find.text('Bio'), findsNothing);
    // One Edit, in the profile card.
    expect(find.text('Edit'), findsOneWidget);
    await t.tap(find.text('People').first);
    await _settle(t);
    expect(find.byType(FollowListsScreen), findsOneWidget);
    await t.pageBack();
    await _settle(t);
    await t.tap(find.text('Blocked').first);
    await _settle(t);
    expect(find.byType(BlockedUsersScreen), findsOneWidget);
    expect(find.text('You haven’t blocked anyone.'), findsOneWidget);
  });

  test('Discovery preferences: Women shows only women, Men only men, both or Everyone show all', () async {
    final (b, _) = await _world();
    Future<Set<String?>> shown(List<String> g) async {
      await b.updateProfile(ProfilePatch({ProfilePatch.prefGenders: g}));
      return (await b.fetchFeed()).map((p) => p.gender).toSet();
    }

    expect(await shown(['woman']), {'woman'});
    expect(await shown(['man']), {'man'});
    final both = await shown(['woman', 'man']);
    expect(both.containsAll({'woman', 'man'}), isTrue);
    final everyone = await shown([]);
    expect(everyone.containsAll({'woman', 'man'}), isTrue);
  });

  testWidgets('Followers and Following are separate lists with a switch', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const FollowListsScreen()));
    await _settle(t);
    final f = all.where((c) => c.followsMe).toList();
    final g = all.where((c) => c.iFollow).toList();
    expect(find.text('Followers ${f.length}'), findsOneWidget);
    expect(find.text('Following ${g.length}'), findsOneWidget);
    expect(find.text('People who follow you. Only you can see this.'), findsOneWidget);
    if (g.isNotEmpty) {
      await t.tap(find.text('Following ${g.length}'));
      await _settle(t);
      expect(find.text('People you follow. Only you can see this.'), findsOneWidget);
    }
  });

  testWidgets('Blocked users: listed after blocking, Unblock removes it and the connection stays gone', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final victim = all.first;
    await t.runAsync(() => b.blockUser(victim.profile.id));
    await t.pumpWidget(_app(b, const BlockedUsersScreen()));
    await _settle(t);
    expect(find.text(victim.profile.firstName), findsOneWidget);
    await t.tap(find.text('Unblock'));
    await _settle(t);
    expect(find.text('You haven’t blocked anyone.'), findsOneWidget);
    final after = (await t.runAsync(b.connections))!;
    expect(after.map((c) => c.profile.id), isNot(contains(victim.profile.id)));
  });

  testWidgets('Suggestions carousel: shows the details, Request and Pass call back, a swipe moves to the next card', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    final items = (await t.runAsync(() => b.suggestions(limit: 3)))!;
    expect(items.length, greaterThanOrEqualTo(2));
    final requested = <String>[];
    final passed = <String>[];
    await t.pumpWidget(
      _app(
        b,
        Scaffold(
          body: SuggestionCarousel(
            items: items,
            onOpen: (_) {},
            onRequest: (s) => requested.add(s.profile.id),
            onPass: (s) => passed.add(s.profile.id),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining(items.first.profile.firstName), findsWidgets);
    expect(find.textContaining('${items.first.compatibility}% match'), findsWidgets);
    await t.tap(find.text('Request').first);
    await t.tap(find.byIcon(Icons.close_rounded).first);
    expect(requested, [items.first.profile.id]);
    expect(passed, [items.first.profile.id]);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining(items[1].profile.firstName), findsWidgets);
  });

  testWidgets('Chats: tapping a chat opens it directly', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final chat = all.firstWhere((c) => c.hasChat);
    await t.pumpWidget(_app(b, const ChatsScreen()));
    await _settle(t);
    await t.tap(find.text(chat.profile.firstName).first);
    await _settle(t, 800);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('Chat: edit a sent message ("edited" tag) and delete it for everyone ("Message deleted")', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final peer = all.firstWhere((c) => c.hasChat).profile;
    await t.runAsync(() => b.sendText(peer.id, 'Helo there'));
    await t.pumpWidget(_app(b, ChatScreen(peer: peer)));
    await _settle(t, 800);
    expect(find.text('Helo there'), findsOneWidget);
    // long-press: Edit
    await t.longPress(find.text('Helo there'));
    await _settle(t);
    await t.tap(find.text('Edit'));
    await _settle(t);
    expect(find.text('Editing message'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Hello there');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await _settle(t, 800);
    expect(find.text('Hello there'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);
    // long-press: Delete for everyone
    await t.longPress(find.text('Hello there'));
    await _settle(t);
    await t.tap(find.text('Delete for everyone'));
    await _settle(t);
    await t.tap(find.text('Delete for everyone'));
    await _settle(t, 800);
    expect(find.text('Message deleted'), findsWidgets);
    expect(find.text('Hello there'), findsNothing);
  });

  testWidgets('Help chat: choose a topic, describe the problem, the request is sent with a ticket number and no instant answer', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const ContactSupportScreen()));
    await _settle(t);
    expect(find.text('Hi, this is Vouby Help. What do you need help with?'), findsOneWidget);
    await t.tap(find.text('Chat and messaging'));
    await _settle(t);
    await t.enterText(find.byType(TextField), 'Voice notes sometimes stop playing');
    await t.pump();
    await t.tap(find.byTooltip('Send'));
    await _settle(t, 1200);
    expect(find.textContaining('Ticket number'), findsOneWidget);
    expect(find.textContaining('isn’t instant'), findsOneWidget);
    expect(find.textContaining('screenshot'), findsNothing);
  });
}
