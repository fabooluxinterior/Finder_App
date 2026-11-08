import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/widgets.dart';
import '../../models/security.dart';
import '../../providers.dart';

final mfaStateProvider = FutureProvider<MfaState>((ref) async {
  ref.watch(authUserProvider);
  return ref.watch(backendProvider).mfaState();
});

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: true,
    keyboardType: TextInputType.number,
    autofillHints: const [AutofillHints.oneTimeCode],
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
    style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.w700),
    decoration: InputDecoration(labelText: '6-digit code', helperText: AppConfig.isDemo ? 'Demo mode: any 6 digits work' : null),
    onChanged: onChanged,
  );
}

/// Shown after OTP sign-in when the account has two-step verification on.
class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key, required this.factorId});
  final String factorId;

  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).verifyTotp(widget.factorId, _code.text);
      ref.invalidate(mfaStateProvider);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Two-step verification'),
      actions: [TextButton(onPressed: () => ref.read(backendProvider).signOut(), child: const Text('Sign out'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.verified_user_outlined, size: 56),
        const SizedBox(height: 16),
        const Text(
          'Enter the code from your authenticator app to finish signing in.',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _CodeField(controller: _code, onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy || _code.text.length != 6 ? null : _verify, child: const Text('Verify')),
      ],
    ),
  );
}

/// Enrol an authenticator app (TOTP).
class MfaEnrollScreen extends ConsumerStatefulWidget {
  const MfaEnrollScreen({super.key});

  @override
  ConsumerState<MfaEnrollScreen> createState() => _MfaEnrollScreenState();
}

class _MfaEnrollScreenState extends ConsumerState<MfaEnrollScreen> {
  TotpEnrollment? _enrollment;
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(backendProvider)
        .enrollTotp()
        .then((e) {
          if (mounted) setState(() => _enrollment = e);
        })
        .catchError((Object e) {
          if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
        });
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).verifyTotp(_enrollment!.factorId, _code.text);
      ref.invalidate(mfaStateProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Two-step verification is on', icon: Icons.verified_user);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _enrollment;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up two-step verification')),
      body: e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  '1. Open an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password…) and add an account with this setup key:',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          e.secret,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1.5),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy key',
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: e.secret));
                          if (context.mounted) showSnack(context, 'Setup key copied');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Account: Finder · Type: time-based', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 20),
                const Text('2. Enter the 6-digit code the app shows:'),
                const SizedBox(height: 8),
                _CodeField(controller: _code, onChanged: (_) => setState(() {})),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy || _code.text.length != 6 ? null : _verify, child: const Text('Turn on')),
              ],
            ),
    );
  }
}
