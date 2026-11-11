import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// Whether the signed-in account has a confirmed email.
final emailConfirmedProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return false;
  return ref.watch(backendProvider).hasConfirmedEmail();
});

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Asked right after the mobile number is verified (new accounts), or opened
/// from the "small update" prompt (existing phone-only accounts). The email
/// is attached to the account once it is confirmed: with the 6-digit code
/// when the email shows one, or by opening the link in the email (the screen
/// notices by itself, so both kinds of email work).
class AddEmailScreen extends ConsumerStatefulWidget {
  const AddEmailScreen({super.key, this.inSetup = false});

  /// Part of sign-up: no back button; a sign-out link instead.
  final bool inSetup;

  @override
  ConsumerState<AddEmailScreen> createState() => _AddEmailScreenState();
}

class _AddEmailScreenState extends ConsumerState<AddEmailScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  Timer? _poll;

  String get _address => _email.text.trim().toLowerCase();
  bool get _valid => _emailPattern.hasMatch(_address);

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _send() {
    if (_busy) return;
    if (!_valid) {
      showSnack(context, 'Enter a valid email address.');
      return;
    }
    _run(() async {
      await ref.read(backendProvider).sendEmailCode(_address);
      setState(() => _codeSent = true);
      _startPolling();
    });
  }

  /// Emails that carry a link instead of a code: check every few seconds
  /// whether the address has been confirmed, then continue.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      bool done = false;
      try {
        done = await ref.read(backendProvider).hasConfirmedEmail();
      } catch (_) {}
      if (done) _finish();
    });
  }

  void _finish() {
    _poll?.cancel();
    ref.invalidate(emailConfirmedProvider);
    ref.invalidate(profileUpdatesProvider);
    if (!mounted) return;
    showSnack(context, 'Email added', icon: PhosphorIconsFill.checkCircle);
    if (!widget.inSetup && Navigator.canPop(context)) Navigator.pop(context);
  }

  void _verify() {
    if (_busy || _code.text.length != 6) return;
    _run(() async {
      await ref.read(backendProvider).verifyEmailCode(_address, _code.text);
      _finish();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.inSetup ? null : AppBar(),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsFill.checkCircle, size: 18, color: c.ok),
                  const SizedBox(width: 6),
                  Text(
                    'Mobile number verified',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink2),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Add your email',
                style: TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: c.ink),
              ),
              const SizedBox(height: 10),
              Text(
                'We use it for account and support messages only. It’s never shown on your profile.',
                style: TextStyle(fontSize: 15, height: 22 / 15, color: c.muted),
              ),
              const SizedBox(height: 28),
              if (!_codeSent) ...[
                TextField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.go,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.ink),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
                    hintText: 'Email',
                    prefixIcon: Icon(PhosphorIconsRegular.envelopeSimple, color: c.muted),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 16),
                PillButton(label: 'Send code', height: 58, busy: _busy, onTap: _valid ? _send : null),
              ] else ...[
                Text(
                  'We emailed $_address. Open the link in that email and this screen continues by itself. '
                  'If the email shows a 6-digit code instead, enter it below.',
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(letterSpacing: 12),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '••••••',
                    helperText: AppConfig.isDemo ? 'Demo: any 6 digits work' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 10),
                PillButton(label: 'Verify email', height: 58, busy: _busy, onTap: _code.text.length == 6 ? _verify : null),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _codeSent = false;
                          _code.clear();
                        }),
                  child: Text('Change email', style: t.labelMedium?.copyWith(color: c.ink2)),
                ),
                TextButton(
                  onPressed: _busy ? null : _send,
                  child: Text('Resend code', style: t.labelMedium?.copyWith(color: c.muted)),
                ),
              ],
              if (widget.inSetup) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _busy ? null : () => ref.read(backendProvider).signOut(),
                  child: Text('Use a different mobile number', style: t.labelMedium?.copyWith(color: c.muted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
