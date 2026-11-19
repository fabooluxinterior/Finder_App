import 'dart:typed_data';

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/data/purchases_service.dart';
import 'package:finder_app/features/chat/chat_screen.dart';
import 'package:finder_app/features/chats/chats_screen.dart';
import 'package:finder_app/features/help/help_center_screen.dart';
import 'package:finder_app/features/help/raise_ticket_screen.dart';
import 'package:finder_app/features/help/support_chat_screen.dart';
import 'package:finder_app/features/help/ticket_detail_screen.dart';
import 'package:finder_app/models/support.dart';
import 'package:finder_app/features/profile/blocked_users_screen.dart';
import 'package:finder_app/features/profile/follow_lists_screen.dart';
import 'package:finder_app/features/profile/my_profile_screen.dart';
import 'package:finder_app/features/suggestions/suggestion_carousel.dart';
import 'package:finder_app/models/follow_request.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('Chat: emoji button on the left of the bar, photo button on the right, menu has Disappearing messages', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final peer = all.firstWhere((c) => c.hasChat).profile;
    await t.pumpWidget(_app(b, ChatScreen(peer: peer)));
    await _settle(t, 800);
    SharedPreferences.setMockInitialValues({}); // the emoji keyboard keeps your recent emoji
    final emoji = find.byTooltip('Emoji');
    final photo = find.byTooltip('Attach');
    expect(emoji, findsOneWidget);
    expect(photo, findsOneWidget);
    expect(t.getCenter(emoji).dx, lessThan(t.getCenter(find.byType(TextField)).dx), reason: 'emoji on the left of the bar');
    expect(t.getCenter(photo).dx, greaterThan(t.getCenter(find.byType(TextField)).dx), reason: 'photo icon on the right');
    await t.tap(emoji);
    await _settle(t);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400))); // the emoji library loads
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('😂').first);
    await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '😂');
    await t.tap(find.byTooltip('Show menu'));
    await _settle(t);
    expect(find.text('Disappearing messages'), findsOneWidget);
    expect(find.text('Scheduled messages'), findsOneWidget, reason: 'its own section in the chat menu');
    await t.tap(find.text('Disappearing messages'));
    await _settle(t);
    expect(find.text('24 hours'), findsOneWidget);
    expect(find.text('7 days'), findsOneWidget);
    expect(find.text('1 month'), findsOneWidget);
    await t.tap(find.text('7 days'));
    await _settle(t, 800);
    expect(find.textContaining('Messages disappear after 7 days'), findsWidgets);
  });

  testWidgets('Chat: a message that arrives while the phone is locked stays unread until the app is back', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final peer = all.firstWhere((c) => c.hasChat).profile;
    await t.pumpWidget(_app(b, ChatScreen(peer: peer)));
    await _settle(t, 800);
    Future<bool> unread() async =>
        (await t.runAsync(() => b.watchMessages(peer.id).first))!.any((m) => m.receiverId == b.currentUserId && !m.isRead);
    expect(await unread(), isFalse, reason: 'the open chat is read');

    // The screen locks: the chat is still open, but nothing may be read by a sleeping phone.
    for (final st in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      t.binding.handleAppLifecycleStateChanged(st);
    }
    await t.pump();
    b.receiveForTest(peer.id, 'Are you there?');
    await _settle(t, 800);
    expect(await unread(), isTrue, reason: 'arrived while locked: unread');

    // Unlocking reads it.
    for (final st in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(st);
    }
    await _settle(t, 800);
    expect(await unread(), isFalse, reason: 'read once the app is back in front');
  });

  testWidgets('Chat: reply from the message menu shows a preview bar, the quote in the sent bubble, and Message info', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final peer = all.firstWhere((c) => c.hasChat).profile;
    await t.runAsync(() => b.sendText(peer.id, 'Original question'));
    await t.pumpWidget(_app(b, ChatScreen(peer: peer)));
    await _settle(t, 800);
    await t.longPress(find.text('Original question'));
    await _settle(t);
    await t.tap(find.text('Reply'));
    await _settle(t);
    expect(find.textContaining('Replying to'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'My answer');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Send'));
    await _settle(t, 800);
    expect(find.textContaining('Replying to'), findsNothing, reason: 'the bar closes after sending');
    expect(find.text('My answer'), findsOneWidget);
    expect(find.text('Original question'), findsNWidgets(2), reason: 'the original and its quote inside the reply');
    // Message info on the sent reply.
    await t.longPress(find.text('My answer'));
    await _settle(t);
    await t.tap(find.text('Message info'));
    await _settle(t);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
  });

  testWidgets('Chat: swiping a message to the left starts a reply; the latest-messages arrow shows when scrolled up', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, all) = (await t.runAsync(_world))!;
    final peer = all.firstWhere((c) => c.hasChat).profile;
    await t.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await b.sendText(peer.id, 'Message number $i');
      }
    });
    await t.pumpWidget(_app(b, ChatScreen(peer: peer)));
    await _settle(t, 800);
    expect(find.byTooltip('Latest messages'), findsOneWidget);
    expect(
      t
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.byTooltip('Latest messages'), matching: find.byType(AnimatedOpacity)).last,
          )
          .opacity,
      0,
    );
    await t.drag(find.byType(ListView).first, const Offset(0, 900));
    await t.pump(const Duration(milliseconds: 500));
    expect(
      t
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.byTooltip('Latest messages'), matching: find.byType(AnimatedOpacity)).last,
          )
          .opacity,
      1,
    );
    await t.tap(find.byTooltip('Latest messages'));
    await t.pump(); // the scroll animation starts on the first frame
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 400));
    expect(
      t
          .widget<AnimatedOpacity>(
            find.ancestor(of: find.byTooltip('Latest messages'), matching: find.byType(AnimatedOpacity)).last,
          )
          .opacity,
      0,
    );
    final g = await t.startGesture(t.getCenter(find.text('Message number 39')));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-15, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await _settle(t);
    expect(find.textContaining('Replying to'), findsOneWidget);
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

  testWidgets('Help chat: welcome, topic buttons, typing, a matching answer, "solved?" and the ticket button', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const SupportChatScreen()));
    await _settle(t);
    expect(find.text('Hi! Welcome to Vouby Support. How can we help you today?'), findsOneWidget);
    expect(find.text('Chat & Messages'), findsOneWidget);
    expect(find.textContaining('Connect to'), findsNothing, reason: 'no live agent option');
    expect(find.textContaining('screenshot'), findsNothing);
    await t.tap(find.text('Chat & Messages'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Vouby Help is typing'), findsOneWidget, reason: 'the assistant types before it answers');
    await _settle(t, 2600);
    expect(find.textContaining('common questions about chat'), findsOneWidget);
    // Type a question the demo FAQ can answer.
    await t.enterText(find.byType(TextField), 'how do I delete my account');
    await t.pump();
    await t.tap(find.byTooltip('Send'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('how do I delete my account'), findsOneWidget);
    await _settle(t, 2600);
    await _settle(t, 2600);
    expect(find.text('Did that solve your issue?'), findsOneWidget);
    expect(find.text('No, I still need help'), findsOneWidget);
    await t.ensureVisible(find.text('No, I still need help'));
    await t.tap(find.text('No, I still need help'));
    await _settle(t, 2600);
    expect(find.text('Raise a Support Ticket'), findsOneWidget);
    // Nonsense falls back to "rephrase or raise a ticket".
    await t.enterText(find.byType(TextField), 'qqqq zzzz');
    await t.pump();
    await t.tap(find.byTooltip('Send'));
    await _settle(t, 2600);
    await _settle(t, 2600);
    expect(find.textContaining('rephrase'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Raise a Support Ticket'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Raise a Support Ticket'), findsOneWidget);
    // The conversation is kept.
    final saved = (await t.runAsync(b.lastBotConversation))!;
    expect(saved.messages.any((m) => m['text'] == 'how do I delete my account'), isTrue);
  });

  testWidgets('Raise a ticket: form with category, title, details, priority; opens the ticket; staff reply, reopen and rating', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const RaiseTicketScreen(category: SupportCategory.chat)));
    await _settle(t);
    expect(find.text('Issue category'), findsOneWidget);
    expect(find.textContaining('screenshot'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'A short summary'), 'Voice notes');
    await t.enterText(
      find.widgetWithText(TextField, 'What happened? What did you expect?'),
      'Voice notes stop after a few seconds',
    );
    await t.tap(find.text('High'));
    await t.pump();
    await t.tap(find.text('Submit ticket'));
    await _settle(t, 800);
    expect(find.byType(TicketDetailScreen), findsOneWidget);
    final ticket = (await t.runAsync(b.myTickets))!.single;
    expect((ticket.priority, ticket.category, ticket.subject), (TicketPriority.high, SupportCategory.chat, 'Voice notes'));
    expect(find.text(ticket.ticketNo), findsWidgets);
    // Reply as the user.
    await t.enterText(
      find.descendant(of: find.byType(TicketDetailScreen), matching: find.byType(TextField)),
      'It happens on Wi-Fi only',
    );
    await t.pump();
    await t.tap(find.byTooltip('Send'));
    await _settle(t, 800);
    expect(find.text('It happens on Wi-Fi only'), findsOneWidget);
    // The team resolves it: the user can reopen or rate.
    b.setTicketStatusForTest(ticket.id, TicketStatus.resolved);
    await t.pump(const Duration(seconds: 11));
    await _settle(t, 800);
    expect(find.text('Reopen ticket'), findsOneWidget);
    expect(find.text('Rate support'), findsOneWidget);
    await t.tap(find.text('Rate support'));
    await _settle(t);
    await t.tap(find.byTooltip('5 stars'));
    await t.pump();
    await t.tap(find.text('Send'));
    await _settle(t, 800);
    expect((await t.runAsync(b.myTickets))!.single.rating, 5);
    await t.tap(find.text('Reopen ticket'));
    await _settle(t, 800);
    expect((await t.runAsync(b.myTickets))!.single.status, TicketStatus.open);
  });

  testWidgets('Help & Support home: search, the seven topics, Help chat and My support tickets', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final (b, _) = (await t.runAsync(_world))!;
    await t.pumpWidget(_app(b, const HelpCenterScreen()));
    await _settle(t);
    for (final label in [
      'Account & Login',
      'Profile & Verification',
      'Matches & Likes',
      'Chat & Messages',
      'Payments & Subscription',
      'Safety & Reporting',
      'Technical Issues',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Help chat'), findsOneWidget);
    expect(find.text('My support tickets'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'delete');
    await t.pump(const Duration(milliseconds: 400));
    await _settle(t);
    expect(find.text('How do I delete my account?'), findsOneWidget);
  });
}
