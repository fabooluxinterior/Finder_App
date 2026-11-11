import 'dart:typed_data';

import 'package:finder_app/core/errors.dart';
import 'package:finder_app/core/theme.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/profile_builder/profile_update_banner.dart';
import 'package:finder_app/models/profile_update.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.filled(n, 7));

/// A live (onboarded) demo user without a profession: an existing account
/// from before the Profession detail was introduced.
Future<DemoBackend> _existingUser({String? occupation, bool prefs = true, bool email = true}) async {
  final b = DemoBackend();
  await b.verifyOtp(OtpChannel.phone, '+919876543210', '123456');
  if (email) {
    await b.sendEmailCode('asha@example.com');
    await b.verifyEmailCode('asha@example.com', '123456');
  }
  await b.setDob(DateTime(1998, 3, 3));
  await b.acknowledgeStandards('2026-11-11');
  await b.createProfile(
    fullName: 'Asha Menon',
    city: 'Kochi',
    details: ProfilePatch({
      ProfilePatch.gender: 'woman',
      ProfilePatch.bio: 'Filter coffee and long walks by the sea.',
      ProfilePatch.occupation: ?occupation,
      if (prefs) ProfilePatch.prefGenders: const ['man'],
      ProfilePatch.interestTags: const ['Hiking', 'Chess', 'Poetry', 'Baking', 'Cycling'],
      ProfilePatch.prompts: const [
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
  group('profile updates (details introduced after launch)', () {
    test('only users missing the detail are asked', () async {
      final missing = await _existingUser();
      final updates = await missing.profileUpdates();
      expect(updates.map((u) => (u.key, u.label, u.showPrompt)), [('occupation', 'Profession', true)]);

      final has = await _existingUser(occupation: 'Architect');
      expect(await has.profileUpdates(), isEmpty);
    });

    test('shown at most once every 7 days; dismiss stops it; unknown keys refused', () async {
      final b = await _existingUser();
      await b.markProfileUpdateSeen('occupation');
      expect((await b.profileUpdates()).single.showPrompt, isFalse, reason: 'just shown');
      await b.dismissProfileUpdate('occupation');
      expect((await b.profileUpdates()).single.showPrompt, isFalse);
      await expectLater(b.markProfileUpdateSeen('nope'), throwsA(isA<AppException>()));
    });

    test('completing saves only that field and keeps everything else', () async {
      final b = await _existingUser();
      final before = (await b.myProfile())!;
      final photos = await b.photoSlots();
      await b.updateProfile(const ProfilePatch({ProfilePatch.occupation: 'Teacher'}));
      final after = (await b.myProfile())!;
      expect(after.occupation, 'Teacher');
      expect(await b.profileUpdates(), isEmpty);
      expect(
        (after.fullName, after.bio, after.city, after.gender, after.interestTags, after.isOnboarded),
        (before.fullName, before.bio, before.city, before.gender, before.interestTags, before.isOnboarded),
      );
      expect((await b.photoSlots()).map((p) => p.mediaId), photos.map((p) => p.mediaId));
    });

    test('discovery preferences: asked only until chosen once', () async {
      final b = await _existingUser(occupation: 'Architect', prefs: false);
      expect((await b.profileUpdates()).map((u) => u.key), ['discovery_prefs']);
      await b.updateProfile(const ProfilePatch({ProfilePatch.prefAgeMin: 18}));
      expect(await b.profileUpdates(), isEmpty, reason: 'saving (even the defaults) counts as choosing');
    });

    test('email: phone-only accounts are asked (optional) until they confirm one', () async {
      final b = await _existingUser(occupation: 'Architect', email: false);
      expect(await b.hasConfirmedEmail(), isFalse);
      final u = (await b.profileUpdates()).single;
      expect((u.key, u.form, u.optional), ('email', 'email', true));
      await expectLater(b.verifyEmailCode('a@b.co', '123456'), throwsA(isA<AppException>()), reason: 'no code sent yet');
      await b.sendEmailCode('Asha@Example.com');
      await b.verifyEmailCode('asha@example.com', '654321');
      expect(await b.hasConfirmedEmail(), isTrue);
      expect(await b.profileUpdates(), isEmpty);
      expect(await b.supportEmail(), 'asha@example.com');
    });

    test('summary for the You tab', () {
      const opt = ProfileUpdate(key: 'a', label: 'A', description: 'Optional thing');
      const req = ProfileUpdate(key: 'b', label: 'B', description: 'Required thing', level: ProfileUpdateLevel.required);
      expect(summarizeUpdates(const []), ProfileUpdateSummary.complete);
      expect(summarizeUpdates(const [opt]), ProfileUpdateSummary.optional);
      expect(summarizeUpdates(const [opt, req]), ProfileUpdateSummary.required);
    });
  });

  testWidgets('banner: shown once, "Not now" hides it, and it is marked as shown', (tester) async {
    late DemoBackend b;
    await tester.runAsync(() async => b = await _existingUser());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(b)],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: ProfileUpdateBanner()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Your profile needs a small update'), findsOneWidget);
    expect(find.textContaining('Profession'), findsOneWidget);
    expect(find.text('Complete profile'), findsOneWidget);

    await tester.tap(find.byTooltip('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Your profile needs a small update'), findsNothing);
    expect((await b.profileUpdates()).single.showPrompt, isFalse, reason: 'not shown again for 7 days');
  });
}
