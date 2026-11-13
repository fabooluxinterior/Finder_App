import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

/// Staff sign-in with a mobile number and SMS code (accounts must already
/// exist; no sign-up). Same number and code as in the Vouby app.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on AdminException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
    await widget.api.sendPhoneCode(_phone.text);
    _sent = true;
  });

  Future<void> _verify() => _run(() => widget.api.verifyPhoneCode(_phone.text, _code.text));

  @override
  Widget build(BuildContext context) => _AuthCard(
    title: 'Vouby admin',
    subtitle: _sent
        ? 'Enter the 6-digit code sent to +91 ${_phone.text.trim()}.'
        : 'Staff only. Sign in with your mobile number.',
    demo: widget.api.isDemo,
    error: _error,
    children: [
      if (!_sent)
        TextField(
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91  '),
          onSubmitted: (_) => _send(),
        )
      else
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Code'),
          onSubmitted: (_) => _verify(),
        ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : (_sent ? _verify : _send), child: Text(_sent ? 'Sign in' : 'Send code')),
      if (_sent)
        TextButton(onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use another number')),
    ],
  );
}

/// Two-step verification with the authenticator set up in the Vouby app.
class MfaPage extends StatefulWidget {
  const MfaPage({super.key, required this.api, required this.onDone});
  final AdminApi api;
  final VoidCallback onDone;

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final _code = TextEditingController();
  late final Future<bool> _has = widget.api.hasAuthenticator();
  bool _busy = false;
  String? _error;

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verifyAuthenticator(_code.text);
      widget.onDone();
    } on AdminException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _has,
    builder: (context, s) {
      if (s.data == false) {
        return MessagePage(
          title: 'Two-step verification needed',
          body:
              'Staff accounts must use an authenticator app. Set it up in the Vouby app '
              '(You → Security → Two-step verification), then sign in here again.',
          action: 'Sign out',
          onAction: widget.api.signOut,
        );
      }
      return _AuthCard(
        title: 'Two-step verification',
        subtitle: 'Enter the 6-digit code from your authenticator app.',
        demo: widget.api.isDemo,
        error: _error,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: const InputDecoration(labelText: 'Authenticator code'),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _verify, child: const Text('Verify')),
          TextButton(onPressed: widget.api.signOut, child: const Text('Sign out')),
        ],
      );
    },
  );
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.title, required this.subtitle, required this.children, this.error, this.demo = false});
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? error;
  final bool demo;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: const TextStyle(color: muted)),
                  if (demo) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Sample data preview: any 10-digit number and any 6 digits work.',
                      style: TextStyle(color: warnAmber),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ...children,
                  if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: accent))],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
