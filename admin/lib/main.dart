import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'demo_api.dart';
import 'login.dart';
import 'models.dart';
import 'shell.dart';
import 'ui.dart';

/// Public values only (the anon key is designed to be public; every admin
/// action is authorised in the database). Never pass a service-role key here.
const _url = String.fromEnvironment('SUPABASE_URL');
const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');
const _demo = bool.fromEnvironment('ADMIN_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdminApi? api;
  if (_demo) {
    api = DemoAdminApi();
  } else if (_url.isNotEmpty && _anon.isNotEmpty) {
    await Supabase.initialize(url: _url, publishableKey: _anon);
    api = SupabaseAdminApi(_url);
  }
  runApp(AdminApp(api: api));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.api});
  final AdminApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vouby Admin',
    debugShowCheckedModeBanner: false,
    theme: adminTheme(),
    home: api == null ? const _NotConfigured() : AccessGate(api: api!),
  );
}

/// Signed out → mobile number + SMS code → authenticator → staff check → admin shell.
class AccessGate extends StatefulWidget {
  const AccessGate({super.key, required this.api});
  final AdminApi api;

  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> {
  late Future<StaffAccess> _access = widget.api.access();

  @override
  void initState() {
    super.initState();
    widget.api.authChanges().listen((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    final next = widget.api.access();
    setState(() {
      _access = next;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StaffAccess>(
    future: _access,
    builder: (context, snap) {
      if (snap.hasError) {
        return MessagePage(title: 'Couldn’t check your access', body: '${snap.error}', action: 'Try again', onAction: _refresh);
      }
      final access = snap.data;
      if (access == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return switch (access) {
        StaffAccess.signedOut => LoginPage(api: widget.api),
        StaffAccess.needsMfa => MfaPage(api: widget.api, onDone: _refresh),
        StaffAccess.noAccess => MessagePage(
          title: 'No access',
          body: 'This account isn’t on the Vouby staff list. Ask an admin to add you.',
          action: 'Sign out',
          onAction: widget.api.signOut,
        ),
        StaffAccess.moderator || StaffAccess.admin => AdminShell(api: widget.api, isAdmin: access == StaffAccess.admin),
      };
    },
  );
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const MessagePage(
    title: 'Admin app isn’t configured',
    body:
        'Build it with --dart-define=SUPABASE_URL=… and --dart-define=SUPABASE_ANON_KEY=… '
        '(public values from Supabase → Settings → API). '
        'For a preview with sample data use --dart-define=ADMIN_DEMO=true.',
  );
}
