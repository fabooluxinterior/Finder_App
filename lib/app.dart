import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'providers.dart';

class FinderApp extends StatelessWidget {
  const FinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finder',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => AppConfig.isDemo
          ? Banner(
              message: 'DEMO',
              location: BannerLocation.topEnd,
              color: AppColors.gold,
              child: child!,
            )
          : child!,
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
          data: (p) => p == null ? const ProfileSetupScreen(isOnboarding: true) : const HomeShell(),
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
