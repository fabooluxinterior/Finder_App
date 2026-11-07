import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/demo_backend.dart';
import 'data/purchases_service.dart';
import 'data/supabase_backend.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.isDemo) {
    final demo = DemoBackend();
    runApp(ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(demo),
        purchasesProvider.overrideWithValue(DemoPurchases(demo)),
      ],
      child: const FinderApp(),
    ));
    return;
  }

  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  runApp(ProviderScope(
    overrides: [
      backendProvider.overrideWithValue(SupabaseBackend(Supabase.instance.client)),
      purchasesProvider.overrideWithValue(RevenueCatPurchases()),
    ],
    child: const FinderApp(),
  ));
}
