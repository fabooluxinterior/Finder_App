import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/feedback.dart';
import 'core/config.dart';
import 'data/demo_backend.dart';
import 'data/purchases_service.dart';
import 'data/supabase_backend.dart';
import 'providers.dart';
import 'security/secure_kv.dart';
import 'security/secure_session_storage.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Fx.instance.init();

  if (AppConfig.isDemo) {
    final demo = DemoBackend(persist: true);
    await demo.restore(); // stay signed in across restarts
    runApp(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(demo), purchasesProvider.overrideWithValue(DemoPurchases(demo))],
        child: const FinderApp(),
      ),
    );
    return;
  }

  if (!AppConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }

  // Rust E2EE core (native library on mobile, WebAssembly on web).
  await RustLib.init();

  final kv = PlatformSecureKv();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      // Mobile: session tokens live in the Android Keystore / iOS Keychain.
      localStorage: kIsWeb ? null : SecureSessionStorage(kv),
    ),
    debug: false,
  );
  runApp(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(SupabaseBackend(Supabase.instance.client, kv: kv)),
        purchasesProvider.overrideWithValue(RevenueCatPurchases()),
      ],
      child: const FinderApp(),
    ),
  );
}

/// Shown by a non-demo build that was compiled without Supabase keys.
class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This build has no server configuration.\n\n'
            'Build with --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…, '
            'or use the demo: --flavor demo --dart-define=DEMO=true',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
