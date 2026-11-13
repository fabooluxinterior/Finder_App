import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vouby_admin/api.dart';
import 'package:vouby_admin/csv.dart';
import 'package:vouby_admin/demo_api.dart';
import 'package:vouby_admin/generated/migrations.g.dart';
import 'package:vouby_admin/main.dart';
import 'package:vouby_admin/models.dart';
import 'package:vouby_admin/models_mod.dart';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test('staff sign in with an Indian mobile number in any common format', () {
    expect(normalizeIndianPhone('9188774739'), '+919188774739');
    expect(normalizeIndianPhone('+91 91887-74739'), '+919188774739');
    expect(normalizeIndianPhone('919188774739'), '+919188774739');
    expect(normalizeIndianPhone('09188774739'), '+919188774739');
    for (final bad in ['', '12345', '5188774739', '91887747390', 'abc']) {
      expect(() => normalizeIndianPhone(bad), throwsA(isA<AdminException>()), reason: bad);
    }
    expect(formatIdentity('919188774739', null), '+91 91887 74739');
    expect(formatIdentity(null, 'a@b.co'), 'a@b.co');
    expect(formatIdentity('', null), isNull);
  });

  test('CSV escapes quotes and neutralises formulas', () {
    expect(
      toCsv([
        ['a,b', 'say "hi"', '=SUM(A1)', null, 3],
      ]),
      '"a,b","say ""hi""",\'=SUM(A1),,3',
    );
  });

  test('migration list comes from the repo and pending = not applied', () {
    expect(repoMigrations.map((m) => m.id), contains('20261114000000_data_completion'));
    final s = SchemaStatus(
      changeLog: const [AppliedMigration(id: '20261107000000_init_finder', description: '', status: 'applied')],
      appliedVersions: const ['20261108000000'],
    );
    expect(s.isApplied('20261107000000_init_finder'), isTrue);
    expect(s.isApplied('20261108000000_security'), isTrue, reason: 'CLI-recorded version counts');
    expect(s.isApplied('20261114000000_data_completion'), isFalse);
  });

  testWidgets('sign-in, two-step, then Database & Data Migration and Integrations', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = DemoAdminApi();
    await t.pumpWidget(AdminApp(api: api));
    await _settle(t);
    expect(find.text('Vouby admin'), findsOneWidget);

    await t.enterText(find.byType(TextField), '9188774739');
    await t.tap(find.text('Send code'));
    await _settle(t);
    await t.enterText(find.byType(TextField), '123456');
    await t.tap(find.text('Sign in'));
    await _settle(t);
    expect(find.text('Two-step verification'), findsOneWidget, reason: 'admins need MFA');
    await t.enterText(find.byType(TextField), '654321');
    await t.tap(find.text('Verify'));
    await _settle(t);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Open reports'), findsOneWidget);

    await t.tap(find.text('Database & Data Migration'));
    await _settle(t);
    expect(find.text('Profile updates'), findsOneWidget);
    expect(find.text('Profession'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.textContaining('reset', findRichText: true), findsWidgets, reason: 'states nothing is reset');
    expect(find.widgetWithText(FilledButton, 'Reset'), findsNothing);
    await t.tap(find.text('Send reminder'));
    await _settle(t);
    expect(find.textContaining('Remind again'), findsOneWidget);

    await t.tap(find.text('Integrations & credentials'));
    await _settle(t);
    expect(find.text('Image moderation (Google Vision)'), findsOneWidget);
    expect(find.textContaining('Missing: GOOGLE_VISION_API_KEY'), findsOneWidget);
  });

  test('push: audiences, mobile number needed for one user, and the log', () async {
    final api = DemoAdminApi();
    expect(pushAudiences.keys, ['all', 'free', 'plan', 'user']);
    await expectLater(api.sendPush(title: 'Hi', body: 'There', audience: 'user', phone: '123'), throwsA(isA<AdminException>()));
    final r = await api.sendPush(title: 'Hi', body: 'There', audience: 'plan');
    expect(r.pushConfigured, isTrue);
    expect((await api.pushCampaigns()).single.title, 'Hi');
  });

  test(
    'dashboard: suspend, list in Suspended accounts, unsuspend; notes are required; removal needs an admin to cancel',
    () async {
      final api = DemoAdminApi();
      expect((await api.restricted(status: 'suspended')).map((r) => r.name), ['Rahul Nair']);

      await expectLater(api.applyAction('u0', 'suspended', note: ''), throwsA(isA<AdminException>()));
      expect(await api.applyAction('u0', 'suspended', note: 'Harassment in chats', days: 7), AccountStatus.suspended);
      expect((await api.restricted(status: 'suspended')).map((r) => r.name), containsAll(['Asha Menon', 'Rahul Nair']));
      expect((await api.overview()).n('suspended'), greaterThanOrEqualTo(3));

      await expectLater(api.unsuspend('u0', note: ''), throwsA(isA<AdminException>()));
      expect(await api.unsuspend('u0', note: 'Appeal accepted'), AccountStatus.active);
      expect((await api.restricted(status: 'suspended')).map((r) => r.name), ['Rahul Nair']);

      expect(await api.applyAction('u2', 'remove', note: 'Removal requested'), AccountStatus.removalPending);
      await expectLater(api.unsuspend('u2', note: 'try'), throwsA(isA<AdminException>()));
      expect(await api.applyAction('u2', 'cancel_removal', note: 'Changed their mind'), AccountStatus.active);

      expect((await api.auditLog()).map((a) => a.action), containsAll(['user_suspended', 'user_unsuspend', 'user_remove']));
      expect((await api.searchUsers(query: 'meera')).single.name, 'Meera Pillai');
    },
  );

  testWidgets('dashboard: Suspended accounts page lists the account and Unsuspend restores it', (t) async {
    t.view.physicalSize = const Size(1400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = DemoAdminApi();
    await api.verifyPhoneCode('9188774739', '123456');
    await api.verifyAuthenticator('654321');
    await t.pumpWidget(AdminApp(api: api));
    await _settle(t);
    await t.tap(find.text('Suspended accounts').first);
    await _settle(t);
    expect(find.text('Rahul Nair'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Unsuspend').first);
    await _settle(t);
    await t.enterText(find.byType(TextField).last, 'Appeal accepted');
    await t.tap(find.widgetWithText(FilledButton, 'Unsuspend').last);
    await _settle(t);
    expect(find.text('Rahul Nair'), findsNothing);
    expect((await api.restricted(status: 'suspended')), isEmpty);
  });
}
