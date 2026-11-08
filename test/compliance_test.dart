import 'package:finder_app/core/config.dart';
import 'package:finder_app/core/errors.dart';
import 'package:finder_app/core/theme.dart';
import 'package:finder_app/core/widgets.dart';
import 'package:finder_app/data/backend.dart';
import 'package:finder_app/data/demo_backend.dart';
import 'package:finder_app/features/auth/auth_screen.dart';
import 'package:finder_app/features/legal/consent.dart';
import 'package:finder_app/features/legal/policy_screen.dart';
import 'package:finder_app/features/onboarding/dob.dart';
import 'package:finder_app/models/security.dart';
import 'package:finder_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date of birth', () {
    test('age is computed from the birthday, not the year', () {
      final today = DateTime(2026, 11, 10);
      expect(ageOn(DateTime(2008, 11, 10), today), 18);
      expect(ageOn(DateTime(2008, 11, 11), today), 17);
      expect(ageOn(DateTime(1990, 1, 1), today), 36);
    });

    test('picker limit is exactly 18 years ago, including leap days', () {
      expect(latestAdultDob(DateTime(2026, 11, 10)), DateTime(2008, 11, 10));
      // 29 Feb 2028 -> 18 years earlier (2010) has no 29 Feb -> 28 Feb.
      expect(latestAdultDob(DateTime(2028, 2, 29)), DateTime(2010, 2, 28));
      expect(ageOn(latestAdultDob(DateTime(2028, 2, 29)), DateTime(2028, 2, 29)), 18);
    });

    test('demo backend mirrors the server: 18+, locked, required before profile', () async {
      final b = DemoBackend();
      await b.verifyOtp(OtpChannel.phone, '+919876543210', '123456');
      final draft = ProfileDraft(fullName: 'Asha', city: 'Kochi', bio: '', interests: const []);
      await expectLater(b.saveProfile(draft), throwsA(isA<AppException>().having((e) => e.code, 'code', AppErrorCode.dobRequired)));
      final minor = DateTime.now().subtract(const Duration(days: 365 * 17));
      await expectLater(b.setDob(minor), throwsA(isA<AppException>().having((e) => e.code, 'code', AppErrorCode.underage)));
      expect(await b.setDob(DateTime(1999, 5, 20)), greaterThanOrEqualTo(26));
      await expectLater(b.setDob(DateTime(1990, 1, 1)), throwsA(isA<AppException>().having((e) => e.code, 'code', AppErrorCode.dobLocked)));
      await b.saveProfile(draft);
      expect((await b.myProfile())!.age, ageOn(DateTime(1999, 5, 20)));
    });
  });

  group('consent', () {
    test('policy links resolve to the in-app documents', () {
      expect(Policy.fromHref('PRIVACY_POLICY.md'), Policy.privacy);
      expect(Policy.fromHref('COMMUNITY_GUIDELINES.md'), Policy.guidelines);
      expect(Policy.fromHref('https://example.com'), isNull);
    });

    test('sign-up consent is recorded after login; older versions need re-consent', () async {
      final b = DemoBackend();
      await b.verifyOtp(OtpChannel.phone, '+919876543210', '123456');
      ProviderContainer container() {
        final c = ProviderContainer(overrides: [backendProvider.overrideWithValue(b)]);
        // Keep providers active for the duration of each check.
        c.listen(authUserProvider, (_, _) {});
        c.listen(consentOkProvider, (_, _) {});
        return c;
      }

      SignupConsent.accepted = false;
      var c = container();
      await c.read(authUserProvider.future);
      expect(await c.read(consentOkProvider.future), isFalse, reason: 'never accepted');
      c.dispose();

      SignupConsent.accepted = true;
      c = container();
      await c.read(authUserProvider.future);
      expect(await c.read(consentOkProvider.future), isTrue);
      expect(await b.acceptedPolicyVersion(), AppConfig.policyVersion);
      expect(SignupConsent.accepted, isFalse, reason: 'consumed once recorded');
      c.dispose();

      await b.recordConsent('2020-01-01'); // simulate an outdated acceptance
      c = container();
      await c.read(authUserProvider.future);
      expect(await c.read(consentOkProvider.future), isFalse, reason: 'outdated version must re-consent');
      c.dispose();
    });

    testWidgets('OTP button stays disabled until the 18+ / policies box is ticked', (tester) async {
      SignupConsent.accepted = false;
      await tester.pumpWidget(ProviderScope(
        overrides: [backendProvider.overrideWithValue(DemoBackend())],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const AuthScreen()),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.pump();

      PillButton continueButton() => tester.widget<PillButton>(find.widgetWithText(PillButton, 'Continue'));
      expect(continueButton().onTap, isNull, reason: 'valid number but no consent');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(continueButton().onTap, isNotNull);
      expect(SignupConsent.accepted, isTrue);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(continueButton().onTap, isNull);
    });
  });

  test('"Appears under 18" report hides the profile from discovery (demo mirrors server)', () async {
    final b = DemoBackend();
    await b.verifyOtp(OtpChannel.phone, '+919876543210', '123456');
    final first = (await b.fetchFeed()).first;
    await b.report(first.id, ReportReason.underage, block: false);
    expect((await b.fetchFeed()).map((p) => p.id), isNot(contains(first.id)));
    expect(ReportReason.underage.label, 'Appears under 18');
  });

  group('sign-in keyboard', () {
    Future<DemoBackend> pumpAuth(WidgetTester tester, {double keyboard = 0}) async {
      SignupConsent.accepted = false;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2.625);
      addTearDown(tester.view.reset);
      final backend = DemoBackend();
      await tester.pumpWidget(ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend)],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const AuthScreen()),
      ));
      await tester.pump(const Duration(seconds: 1));
      return backend;
    }

    testWidgets('number field and Continue sit above an open keyboard', (tester) async {
      await pumpAuth(tester, keyboard: 320);
      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final keyboardTop = screenHeight - 320;
      expect(tester.getRect(find.byType(TextField)).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.getRect(find.widgetWithText(PillButton, 'Continue')).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.takeException(), isNull, reason: 'no layout overflow');
    });

    testWidgets('Enter on the keyboard sends the code, then verifies', (tester) async {
      final backend = await pumpAuth(tester);
      await tester.enterText(find.byType(TextField), '9876543210');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Tick the box'), findsOneWidget, reason: 'consent still required');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.showKeyboard(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Enter the code sent to'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(seconds: 1));
      expect(backend.currentUserId, isNotNull, reason: 'signed in via the enter key');
    });
  });
}
