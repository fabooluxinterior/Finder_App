import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

/// The account's contact email (null until one is added). It is only used for
/// account and support notifications: not verified, not used to sign in, never
/// shown to other users.
final contactEmailProvider = FutureProvider<String?>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return null;
  return ref.watch(backendProvider).contactEmail();
});

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Asked right after the mobile number is verified (new accounts), from the
/// "small update" prompt (existing accounts without one) and from You →
/// Email for notifications. One field, one button: no code to enter.
class AddEmailScreen extends ConsumerStatefulWidget {
  const AddEmailScreen({super.key, this.inSetup = false});

  /// Part of sign-up: no back button; a sign-out link instead.
  final bool inSetup;

  @override
  ConsumerState<AddEmailScreen> createState() => _AddEmailScreenState();
}

class _AddEmailScreenState extends ConsumerState<AddEmailScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _prefilled = false;

  String get _address => _email.text.trim().toLowerCase();
  bool get _valid => _address.length <= 254 && _emailPattern.hasMatch(_address);

  Future<void> _save() async {
    if (_busy) return;
    if (!_valid) {
      showSnack(context, 'Enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).setContactEmail(_address);
      ref.invalidate(contactEmailProvider);
      ref.invalidate(profileUpdatesProvider);
      if (!mounted) return;
      showSnack(context, 'Email saved', icon: PhosphorIconsFill.checkCircle);
      if (!widget.inSetup && Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    // Editing: start from the saved address.
    final saved = ref.watch(contactEmailProvider).value;
    if (!_prefilled && saved != null && saved.isNotEmpty) {
      _prefilled = true;
      _email.text = saved;
    }
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
              if (widget.inSetup)
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
              SizedBox(height: widget.inSetup ? 20 : 0),
              Text(
                widget.inSetup ? 'Add your email' : 'Email for notifications',
                style: TextStyle(fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: c.ink),
              ),
              const SizedBox(height: 10),
              Text(
                'We use it for account and support notifications only. It isn’t used to sign in and is never shown on your profile.',
                style: TextStyle(fontSize: 15, height: 22 / 15, color: c.muted),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.ink),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
                  hintText: 'Email',
                  prefixIcon: Icon(PhosphorIconsRegular.envelopeSimple, color: c.muted),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              PillButton(label: 'Continue', height: 58, busy: _busy, onTap: _valid ? _save : null),
              if (widget.inSetup) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _busy ? null : () => ref.read(backendProvider).signOut(),
                  child: Text('Use a different mobile number', style: TextStyle(fontSize: 14, color: c.muted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
