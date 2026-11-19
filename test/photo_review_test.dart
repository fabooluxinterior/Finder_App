import 'package:finder_app/core/theme.dart';
import 'package:finder_app/features/profile_builder/photo_grid.dart';
import 'package:finder_app/models/profile.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PhotoSlot _slot(int i, {bool pending = false}) => PhotoSlot(mediaId: 'm$i', url: '', pending: pending);

void main() {
  testWidgets('a photo in review flips to live by itself, with a message, and the grid explains the wait', (tester) async {
    var approvedOnServer = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoSlotsProvider.overrideWith(
            (ref) async => [for (var i = 0; i < 4; i++) _slot(i, pending: i == 3 && !approvedOnServer)],
          ),
          myProfileProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: SingleChildScrollView(child: PhotoGrid())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('1 in review'), findsOneWidget);
    expect(find.textContaining('at least 4 photos are approved'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget, reason: 'the tile is marked');
    expect(find.textContaining('3 of 6'), findsNothing, reason: 'the live count only counts approved photos');

    // The server approves it; the app notices on its next check (every 6 s).
    approvedOnServer = true;
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('in review'), findsNothing);
    expect(find.text('Photo approved'), findsOneWidget);
    expect(find.textContaining('4 of 6 photos'), findsOneWidget);

    // Nothing left to wait for: the periodic check has stopped (no pending timers).
    await tester.pump(const Duration(seconds: 20));
  });
}
