import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'features/legal/consent.dart';
import 'features/onboarding/dob.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/security/mfa_screens.dart';
import 'providers.dart';

class FinderApp extends StatelessWidget {
  const FinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finder',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider);
    return uid.when(
      loading: () => const _Splash(),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
      data: (id) {
        if (id == null) return const AuthScreen();
        // Accounts with two-step verification must complete it first.
        final mfa = ref.watch(mfaStateProvider);
        if (mfa.isLoading) return const _Splash();
        final m = mfa.value;
        if (m != null && m.needsChallenge) return MfaChallengeScreen(factorId: m.verifiedFactorIds.first);
        // Current policies must be accepted (recorded after sign-up consent).
        final consent = ref.watch(consentOkProvider);
        if (consent.isLoading && !consent.hasValue) return const _Splash();
        if (consent.value != true) return const ReConsentScreen();
        final profile = ref.watch(myProfileProvider);
        return profile.when(
          loading: () => const _Splash(),
          error: (e, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ref.invalidate(myProfileProvider),
                child: Text('$e\nTap to retry', textAlign: TextAlign.center),
              ),
            ),
          ),
          data: (p) {
            if (p == null) return const ProfileSetupScreen(isOnboarding: true);
            // Accounts created before DOBs were required must add one once.
            final dob = ref.watch(hasDobProvider);
            if (dob.isLoading && !dob.hasValue) return const _Splash();
            if (dob.value == false) return const DobRequiredScreen();
            return const HomeShell();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
