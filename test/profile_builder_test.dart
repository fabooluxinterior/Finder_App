import 'dart:typed_data';

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/core/image_optimizer.dart';
import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/deck/profile_card.dart';
import 'package:finder_app/features/onboarding/onboarding_flow.dart';
import 'package:finder_app/models/follow_request.dart';
import 'package:finder_app/models/profile.dart';
import 'package:finder_app/models/profile_catalog.dart';
import 'package:finder_app/models/profile_completion.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  group('image optimizer', () {
    test('fits inside a 1080 px box keeping the aspect ratio, never upscales', () {
      expect(ImageOptimizer.planResize(4032, 3024), (width: 1080, height: 810));
      expect(ImageOptimizer.planResize(3024, 4032), (width: 810, height: 1080));
      expect(ImageOptimizer.planResize(1080, 1920), (width: 608, height: 1080));
      expect(ImageOptimizer.planResize(800, 600), (width: 800, height: 600));
    });

    test('recognises JPEG, PNG, WebP and HEIC by their bytes', () {
      Uint8List h(List<int> head) => Uint8List.fromList([...head, ...List.filled(16, 0)]);
      expect(ImageOptimizer.sniff(h([0xff, 0xd8, 0xff, 0xe0])), ImageFormat.jpeg);
      expect(ImageOptimizer.sniff(h([0x89, 0x50, 0x4e, 0x47])), ImageFormat.png);
      expect(ImageOptimizer.sniff(h('RIFF\x00\x00\x00\x00WEBP'.codeUnits)), ImageFormat.webp);
      expect(ImageOptimizer.sniff(h('\x00\x00\x00\x18ftypheic'.codeUnits)), ImageFormat.heic);
      expect(ImageOptimizer.sniff(h('%PDF-1.7 not a photo'.codeUnits)), isNull);
    });

    test('walks down quality, then size, until under 100 KB', () async {
      final tried = <(int, double)>[];
      final out = await ImageOptimizer.fitUnder(100 * 1024, (q, s) async {
        tried.add((q, s));
        // Pretend size shrinks with quality and scale.
        final size = (q * 2600 * s * s).round();
        return EncodedImage(_bytes(size), 'image/webp');
      });
      expect(out.bytes.lengthInBytes, lessThanOrEqualTo(100 * 1024));
      expect(tried.first, (82, 1.0));
      expect(tried.last.$2, lessThan(1.0), reason: 'quality alone was not enough here');
    });

    test('gives up with a friendly message when nothing fits', () async {
      expect(
        () => ImageOptimizer.fitUnder(100 * 1024, (q, s) async => EncodedImage(_bytes(500 * 1024), 'image/webp')),
        throwsA(isA<ImageOptimizeException>()),
      );
    });
  });

  group('completion score', () {
    test('matches the SQL function on the same inputs', () {
      expect(ProfileCompletion.compute(photos: 0), 0);
      expect(
        ProfileCompletion.compute(
          photos: 4,
          occupation: 'Designer',
          education: 'NIT Calicut',
          lifestyleCount: 6,
          languages: 2,
          tags: 5,
          bio: 'Twenty characters exactly!',
          prompts: 2,
          music: true,
        ),
        100,
      );
      expect(ProfileCompletion.compute(photos: 3, occupation: 'Designer', tags: 2, bio: 'short', prompts: 1), 39);
      expect(ProfileCompletion.compute(photos: 6, tags: 9, prompts: 4), 55);
    });

    test('points to the most valuable missing step', () {
      const base = PublicProfile(id: 'x', fullName: 'A', age: 25, city: 'Kochi', bio: '', primaryPhoto: null, isPremium: false);
      expect(ProfileCompletion.of(base.copyWith(photos: ['a', 'b'])).nextStep, 'Add 2 more photos (+15%)');
      final full = base.copyWith(
        photos: ['a', 'b', 'c', 'd'],
        prompts: const [
          ProfilePrompt(promptId: 'p1', question: 'q', answer: 'a'),
          ProfilePrompt(promptId: 'p2', question: 'q', answer: 'a'),
        ],
        interestTags: const ['A', 'B', 'C', 'D', 'E'],
        bio: 'A bio that is long enough.',
        occupation: 'x',
        education: 'y',
        languages: const ['English'],
        lifestyle: const {'intention': 'a', 'activity': 'b', 'drinking': 'c', 'smoking': 'd', 'zodiac': 'e', 'culture': 'f'},
      );
      expect(ProfileCompletion.of(full).nextStep, 'Connect Spotify (+5%)');
      expect(ProfileCompletion.of(full.copyWith(musicLinked: true)).nextStep, isNull);
    });
  });

  test('prompt cards sit between photos in the browsing stack', () {
    const p = PublicProfile(
      id: 'x',
      fullName: 'A',
      age: 25,
      city: 'Kochi',
      bio: '',
      primaryPhoto: 'a',
      isPremium: false,
      photos: ['a', 'b', 'c', 'd', 'e'],
      prompts: [
        ProfilePrompt(promptId: 'p1', question: 'q1', answer: 'a1'),
        ProfilePrompt(promptId: 'p2', question: 'q2', answer: 'a2'),
      ],
    );
    final order = cardPages(p).map(
      (x) => switch (x) {
        PhotoPage(:final url) => url!,
        PromptPage(:final prompt) => prompt.promptId,
      },
    );
    expect(order, ['a', 'p1', 'b', 'p2', 'c', 'd', 'e']);
  });

  group('demo backend mirrors the server rules', () {
    late DemoBackend b;
    setUp(() async {
      b = DemoBackend();
      await b.verifyOtp(OtpChannel.phone, '+919876543210', '123456');
      await b.setDob(DateTime(1998, 3, 3));
      await b.createProfile(fullName: 'Asha Menon', city: 'Kochi', details: const ProfilePatch({}));
    });

    test('a profile goes live only after every requirement', () async {
      await expectLater(
        b.completeOnboarding(),
        throwsA(
          isA<AppException>().having((e) => e.message, 'missing', allOf(contains('community_standards'), contains('photos'))),
        ),
      );
      await b.acknowledgeStandards('2026-11-11');
      await b.updateProfile(
        ProfilePatch({
          ProfilePatch.gender: 'woman',
          ProfilePatch.interestTags: const ['Hiking', 'Chess', 'Poetry', 'Baking', 'Cycling'],
          ProfilePatch.prompts: const [
            {'prompt_id': 'p1', 'answer': 'Evening chai at Fort Kochi'},
            {'prompt_id': 'p4', 'answer': 'Sunrise, appam, nap'},
          ],
        }),
      );
      for (var i = 0; i < 4; i++) {
        await b.uploadPhoto(_bytes(50 * 1024), mime: 'image/webp');
      }
      await b.completeOnboarding();
      final me = (await b.myProfile())!;
      expect(me.isOnboarded, isTrue);
      expect(me.prompts.first.question, promptById('p1')!.question, reason: 'question comes from the catalog');
    });

    test('photo slots: 6 max, replace in place, reorder must be a permutation, 100 KB cap', () async {
      for (var i = 0; i < 6; i++) {
        await b.uploadPhoto(_bytes(1000 + i), mime: 'image/webp');
      }
      await expectLater(b.uploadPhoto(_bytes(10), mime: 'image/webp'), throwsA(isA<AppException>()));
      await expectLater(b.uploadPhoto(_bytes(200 * 1024), mime: 'image/webp'), throwsA(isA<AppException>()));
      final slots = await b.photoSlots();
      await b.uploadPhoto(_bytes(7), mime: 'image/webp', replaces: slots[2].mediaId);
      final after = await b.photoSlots();
      expect(after.length, 6);
      expect(after[2].mediaId, isNot(slots[2].mediaId));
      await expectLater(b.reorderPhotos([after.first.mediaId]), throwsA(isA<AppException>()));
      await b.reorderPhotos(after.reversed.map((s) => s.mediaId).toList());
      expect((await b.myProfile())!.primaryPhoto, after.last.url);
      await b.removePhoto(after.first.mediaId);
      expect((await b.photoSlots()).length, 5);
    });

    test('prompt answers reject contact details and run 150 characters max', () async {
      await expectLater(
        b.updateProfile(
          const ProfilePatch({
            ProfilePatch.prompts: [
              {'prompt_id': 'p1', 'answer': 'insta: @asha.m'},
            ],
          }),
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', AppErrorCode.contactInfo)),
      );
      await expectLater(
        b.updateProfile(
          ProfilePatch({
            ProfilePatch.prompts: [
              {'prompt_id': 'p1', 'answer': 'a' * 151},
            ],
          }),
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('music: hidden artists leave the public list and never match', () async {
      await b.musicAuthorizeUrl(); // demo imports sample artists
      var me = (await b.myProfile())!;
      expect(me.musicLinked, isTrue);
      final diya = await b.profileCard('u_diya');
      expect(diya.sharedArtists.map((a) => a.name), containsAll(['Sushin Shyam', 'Prateek Kuhad']));

      final sushin = (await b.musicState()).artists.firstWhere((a) => a.name == 'Sushin Shyam');
      await b.setArtistVisibility(sushin.id, visible: false);
      me = (await b.myProfile())!;
      expect(me.topArtists.any((a) => a.id == sushin.id), isFalse);
      expect((await b.profileCard('u_diya')).sharedArtists.any((a) => a.id == sushin.id), isFalse);

      await b.disconnectMusic();
      me = (await b.myProfile())!;
      expect(me.musicLinked, isFalse);
      expect(me.topArtists, isEmpty);
    });

    test('a prompt reply sends a request anchored to that answer', () async {
      await expectLater(b.replyToPrompt('u_arjun', 'p16', 'hi'), throwsA(isA<AppException>()));
      await expectLater(b.replyToPrompt('u_arjun', 'p2', 'call 98765 43210'), throwsA(isA<AppException>()));
      expect(await b.replyToPrompt('u_arjun', 'p2', 'Thalassery, every time.'), SwipeOutcome.requested);
    });
  });

  testWidgets('onboarding starts with the community standards and moves on after agreeing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final backend = DemoBackend();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend)],
        child: MaterialApp(theme: buildTheme(Brightness.dark), home: const OnboardingFlow()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('How Vouby works'), findsOneWidget);
    expect(find.text('Both people say yes'), findsOneWidget);
    await tester.tap(find.text('I agree'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('About you'), findsOneWidget);
    expect(find.text('2/7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
