import 'package:finder_app/features/home/social_refresher.dart';
import 'package:finder_app/models/follow_request.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requests and chats are re-fetched on tab open, on resume and on a timer', (tester) async {
    var requests = 0;
    var connections = 0;
    final tab = ValueNotifier<int>(0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith((ref) async {
            requests++;
            return IncomingRequests(count: requests, requests: const []);
          }),
          connectionsProvider.overrideWith((ref) async {
            connections++;
            return const [];
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              // Something has to listen, as the real screens do.
              ref.watch(incomingRequestsProvider);
              ref.watch(connectionsProvider);
              return ValueListenableBuilder<int>(
                valueListenable: tab,
                builder: (_, t, _) => SocialRefresher(tab: t),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect((requests, connections), (1, 1), reason: 'first load');

    // On Discover nothing is re-fetched for the first three intervals; the fourth refreshes the badges.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 15));
    }
    expect(requests, 1);
    await tester.pump(const Duration(seconds: 15));
    expect((requests, connections), (2, 2), reason: 'every fourth interval keeps the badges honest');

    // Opening the Requests tab re-fetches at once.
    tab.value = 2;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect((requests, connections), (3, 3));

    // While it is open, every interval.
    await tester.pump(const Duration(seconds: 15));
    expect((requests, connections), (4, 4));

    // Returning to the app re-fetches.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect((requests, connections), (5, 5));

    // Switching to a tab that isn't watched does not re-fetch.
    tab.value = 4;
    await tester.pump();
    await tester.pump();
    expect(requests, 5);
  });
}
