import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import 'policy_screen.dart';

/// Ticked on the sign-in screen; recorded on the server right after login.
class SignupConsent {
  SignupConsent._();
  static bool accepted = false;
}

/// True when the signed-in user has accepted the current POLICY_VERSION.
/// A consent given on the sign-in screen is recorded here, after login.
final consentOkProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return false;
  final backend = ref.watch(backendProvider);
  final accepted = await backend.acceptedPolicyVersion();
  final current = accepted != null && accepted.compareTo(AppConfig.policyVersion) >= 0;
  if (current) return true;
  if (SignupConsent.accepted) {
    await backend.recordConsent(AppConfig.policyVersion);
    SignupConsent.accepted = false;
    return true;
  }
  return false;
});

final hasDobProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) return false;
  return ref.watch(backendProvider).hasDob();
});

/// "I'm 18+ and agree to the Terms, Community Guidelines and Privacy Policy",
/// with each document linked.
class ConsentCheckbox extends StatefulWidget {
  const ConsentCheckbox({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<ConsentCheckbox> createState() => _ConsentCheckboxState();
}

class _ConsentCheckboxState extends State<ConsentCheckbox> {
  late final _links = {for (final p in Policy.values) p: TapGestureRecognizer()..onTap = () => openPolicy(context, p)};

  @override
  void dispose() {
    for (final r in _links.values) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final link = TextStyle(color: c.ink, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    return Semantics(
      checked: widget.value,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: widget.value,
              onChanged: (v) => widget.onChanged(v ?? false),
              activeColor: c.ink,
              checkColor: c.paper,
              side: BorderSide(color: c.muted, width: 1.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onChanged(!widget.value),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(
                  TextSpan(
                    style: t.bodySmall?.copyWith(color: c.ink2, height: 1.45),
                    children: [
                      const TextSpan(text: 'I’m 18+ and agree to the '),
                      TextSpan(text: 'Terms', style: link, recognizer: _links[Policy.terms]),
                      const TextSpan(text: ', '),
                      TextSpan(text: 'Community Guidelines', style: link, recognizer: _links[Policy.guidelines]),
                      const TextSpan(text: ' and '),
                      TextSpan(text: 'Privacy Policy', style: link, recognizer: _links[Policy.privacy]),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blocking screen shown when the accepted policy version is older than
/// POLICY_VERSION (or was never recorded).
class ReConsentScreen extends ConsumerStatefulWidget {
  const ReConsentScreen({super.key});

  @override
  ConsumerState<ReConsentScreen> createState() => _ReConsentScreenState();
}

class _ReConsentScreenState extends ConsumerState<ReConsentScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).recordConsent(AppConfig.policyVersion);
      ref.invalidate(consentOkProvider);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(PhosphorIconsRegular.shieldCheck, size: 44, color: c.ink),
              const SizedBox(height: 18),
              Text('We’ve updated our policies', style: t.headlineSmall),
              const SizedBox(height: 8),
              Text('Please review the changes to keep using Vouby.', style: t.bodyMedium?.copyWith(color: c.muted)),
              const SizedBox(height: 20),
              for (final p in Policy.values)
                Pressable(
                  scale: 0.98,
                  onTap: () => openPolicy(context, p),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.hair),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(p.title, style: t.titleMedium)),
                        Icon(PhosphorIconsBold.caretRight, size: 16, color: c.muted),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              ConsentCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
              const SizedBox(height: 14),
              PillButton(label: 'Accept and continue', busy: _busy, onTap: _agreed ? _accept : null),
              TextButton(
                onPressed: () => ref.read(backendProvider).signOut(),
                child: Text('Sign out', style: t.labelMedium?.copyWith(color: c.ink2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
