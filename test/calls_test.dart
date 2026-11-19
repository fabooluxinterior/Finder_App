import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/calls/call_gate.dart';
import 'package:finder_app/features/calls/demo_call_screen.dart';
import 'package:finder_app/models/fun_lines.dart';
import 'package:finder_app/models/profile.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(DemoBackend, PublicProfile)> _peer() async {
  final b = DemoBackend();
  final p = (await b.fetchFeed()).first;
  return (b, p);
}

Widget _host(DemoBackend b, PublicProfile peer, DateTime? since) => ProviderScope(
  overrides: [backendProvider.overrideWithValue(b)],
  child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      appBar: AppBar(
        actions: [CallButton(peer: peer, connectedAt: since)],
      ),
    ),
  ),
);

void main() {
  test('CallGate counts whole days left, rounding up, and opens exactly on time', () {
    final t0 = DateTime(2026, 11, 1, 12);
    expect(CallGate.of(t0, 4, now: t0).daysLeft, 4);
    expect(CallGate.of(t0, 4, now: t0.add(const Duration(days: 1, hours: 1))).daysLeft, 3);
    expect(CallGate.of(t0, 4, now: t0.add(const Duration(days: 3, hours: 23))).daysLeft, 1);
    expect(CallGate.of(t0, 4, now: t0.add(const Duration(days: 4))).open, isTrue);
    expect(CallGate.of(t0, 0, now: t0).open, isTrue, reason: 'an admin can switch the waiting time off');
  });

  test('fun lines: {n} and {name} are filled in; the slot falls back to the built-in lines', () {
    const f = FunLines({
      'call_locked': ['Wait {n} days, {name}'],
    });
    expect(f.pick('call_locked', n: 3, name: 'Asha'), 'Wait 3 days, Asha');
    expect(f.pick('welcome'), isNotEmpty);
    expect(const FunLines({}).pick('nothing_here'), '');
  });

  testWidgets('locked: the lock shows, tapping gives the quote, the fun text and the days left', (t) async {
    final (b, peer) = (await t.runAsync(_peer))!;
    await t.pumpWidget(_host(b, peer, DateTime.now().subtract(const Duration(days: 1))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await t.tap(find.byType(CallButton));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Understand each other first'), findsOneWidget);
    expect(find.text('Opens in 3 days'), findsOneWidget);
    expect(find.textContaining('divasam'), findsWidgets, reason: 'the Malayalam fun text');
    expect(b.startedCalls, isEmpty, reason: 'no call is started while locked');
  });

  testWidgets('open: tapping starts the demo call, which rings, connects, runs a timer and ends', (t) async {
    final (b, peer) = (await t.runAsync(_peer))!;
    await t.pumpWidget(_host(b, peer, DateTime.now().subtract(const Duration(days: 5))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    await t.tap(find.byType(CallButton));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(DemoCallScreen), findsOneWidget);
    expect(find.text('Demo call · no audio yet'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1700));
    expect(find.text('Ringing…'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1900));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    expect(b.startedCalls, [peer.id]);
    await t.tap(find.byIcon(Icons.call_end_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(DemoCallScreen), findsNothing);
  });
}
