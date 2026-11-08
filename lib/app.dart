import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/brand.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'features/legal/consent.dart';
import 'features/onboarding/dob.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/security/mfa_screens.dart';
import 'providers.dart';

class FinderApp extends StatelessWidget {
  const FinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vouby',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: const _Intro(child: _AuthGate()),
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
            // First run (or an unfinished setup): the 7-stage wizard, resumed
            // at the saved stage. The server decides when it's complete.
            if (p == null || !p.isOnboarded) return OnboardingFlow(key: ValueKey(p?.id), profile: p);
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

/// Plays the Vouby opening animation once per launch over whatever the gate
/// resolves to underneath, then fades it away.
class _Intro extends StatefulWidget {
  const _Intro({required this.child});
  final Widget child;

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> {
  bool _done = false;
  bool _gone = false;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          IgnorePointer(
            ignoring: _done,
            child: AnimatedOpacity(
              opacity: _done ? 0 : 1,
              duration: Motion.of(context, const Duration(milliseconds: 260)),
              curve: Motion.easeOut,
              onEnd: () => setState(() => _gone = true),
              child: Scaffold(
                backgroundColor: c.paper,
                body: SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: VoubySplash(
                            onDone: () => Future.delayed(const Duration(milliseconds: 250), () {
                              if (mounted) setState(() => _done = true);
                            }),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Text(
                          'Real people, real conversations.',
                          style: TextStyle(fontSize: 15, height: 22 / 15, color: c.ink.withValues(alpha: 0.85)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
