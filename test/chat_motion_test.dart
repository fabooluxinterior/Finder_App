import 'dart:async';
import 'dart:typed_data';

import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/chat/voice_bubble.dart';
import 'package:finder_app/features/chat/words.dart';
import 'package:finder_app/models/message.dart';
import 'package:finder_app/models/presence.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('what the other person is doing', () {
    test('words and header text for each state', () {
      expect(PeerState.typing.words, 'typing');
      expect(PeerState.recording.words, 'recording audio');
      expect(PeerState.photo.words, 'sending a photo');
      expect(PeerState.typing.header, 'typing…');
      expect(PeerState.recording.header, 'recording audio…');
      expect(PeerState.photo.header, 'sending a photo…');
      expect(PeerState.parse('typing'), PeerState.typing);
      expect(PeerState.parse('nonsense'), PeerState.idle);
      expect(PeerState.parse(null), PeerState.idle);
    });

    testWidgets('typing and recording clear after 4 s without a refresh; a photo after 30 s', (t) async {
      final src = StreamController<PeerState>();
      final seen = <PeerState>[];
      final sub = withDecay(src.stream).listen(seen.add);
      addTearDown(() async {
        await sub.cancel();
        await src.close();
      });
      await t.pump();
      expect(seen.last, PeerState.idle);

      src.add(PeerState.typing);
      await t.pump(const Duration(milliseconds: 3900));
      expect(seen.last, PeerState.typing, reason: 'still within 4 s');
      await t.pump(const Duration(milliseconds: 200));
      expect(seen.last, PeerState.idle, reason: 'cleared by itself');

      src.add(PeerState.recording);
      await t.pump(const Duration(seconds: 3));
      src.add(PeerState.recording); // the 2.5 s refresh
      await t.pump(const Duration(seconds: 3));
      expect(seen.last, PeerState.recording, reason: 'refreshed, so it stays');
      await t.pump(const Duration(seconds: 2));
      expect(seen.last, PeerState.idle);

      src.add(PeerState.photo);
      await t.pump(const Duration(seconds: 29));
      expect(seen.last, PeerState.photo);
      await t.pump(const Duration(seconds: 2));
      expect(seen.last, PeerState.idle);

      src.add(PeerState.typing);
      await t.pump();
      src.add(PeerState.idle); // an explicit "stopped"
      await t.pump();
      expect(seen.last, PeerState.idle);
    });

    testWidgets('the Words line appears for a state and is empty when idle', (t) async {
      await t.pumpWidget(_host(const PeerStateLine(state: PeerState.typing)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('typing'), findsOneWidget);
      await t.pumpWidget(_host(const PeerStateLine(state: PeerState.photo)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('sending a photo'), findsOneWidget);
      await t.pumpWidget(_host(const PeerStateLine(state: PeerState.idle)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('typing'), findsNothing);
      expect(find.text('sending a photo'), findsNothing);
    });

    testWidgets('with reduce motion the words stand still but are still shown', (t) async {
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(const PeerStateLine(state: PeerState.recording)),
        ),
      );
      await t.pump();
      expect(find.text('recording audio'), findsOneWidget);
    });

    test('the demo backend carries signals and the privacy setting defaults to on', () async {
      final b = DemoBackend();
      expect(await b.watchPeerState('x').isEmpty.timeout(const Duration(milliseconds: 50), onTimeout: () => true), isTrue);
      await b.sendPeerState('x', PeerState.typing); // never throws
    });
  });

  group('sent voice note', () {
    final msg = ChatMessage(
      id: 'm1-abcdefgh',
      senderId: 'a',
      receiverId: 'b',
      content: null,
      isRead: true,
      createdAt: DateTime(2026, 11, 12),
      voice: VoiceRef(path: 'p', key: Uint8List(32), nonce: Uint8List(12), sha256: Uint8List(32), millis: 7000),
    );

    testWidgets('shows the words, the length and the speed chip, and the chip steps 1× 1.5× 2×', (t) async {
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        _host(
          VoiceBubble(message: msg, color: Colors.black),
          overrides: [backendProvider.overrideWithValue(DemoBackend())],
        ),
      );
      await t.pump();
      expect(find.text('Voice note'), findsOneWidget);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('1×'), findsOneWidget);
      await t.tap(find.text('1×'));
      await t.pump();
      expect(find.text('1.5×'), findsOneWidget);
      await t.tap(find.text('1.5×'));
      await t.pump();
      expect(find.text('2×'), findsOneWidget);
      await t.tap(find.text('2×'));
      await t.pump();
      expect(find.text('1×'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Play$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Playback speed')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a note already heard says Listened', (t) async {
      VoiceBubble.listened.add(msg.id);
      addTearDown(() => VoiceBubble.listened.remove(msg.id));
      await t.pumpWidget(
        _host(
          VoiceBubble(message: msg, color: Colors.black),
          overrides: [backendProvider.overrideWithValue(DemoBackend())],
        ),
      );
      await t.pump();
      expect(find.text('Listened'), findsOneWidget);
    });
  });
}
