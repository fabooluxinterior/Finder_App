import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  OtpChannel _channel = OtpChannel.phone;
  final _target = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;

  String get _normalizedTarget {
    final t = _target.text.trim();
    if (_channel == OtpChannel.email) return t.toLowerCase();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('91') && digits.length == 12 ? '+$digits' : '+91$digits';
  }

  bool get _targetValid => _channel == OtpChannel.email
      ? RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_target.text.trim())
      : RegExp(r'^\+91[6-9]\d{9}$').hasMatch(_normalizedTarget);

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: Icons.error_outline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = ref.read(backendProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.lock_person_rounded, color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Finder', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1)),
            const SizedBox(height: 6),
            Text('A private network. Profiles unlock only when you both say yes.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
            const SizedBox(height: 32),
            SegmentedButton<OtpChannel>(
              segments: const [
                ButtonSegment(value: OtpChannel.phone, label: Text('Phone'), icon: Icon(Icons.phone_iphone)),
                ButtonSegment(value: OtpChannel.email, label: Text('Email'), icon: Icon(Icons.mail_outline)),
              ],
              selected: {_channel},
              onSelectionChanged: _codeSent
                  ? null
                  : (s) => setState(() {
                        _channel = s.first;
                        _target.clear();
                      }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _target,
              enabled: !_codeSent,
              keyboardType: _channel == OtpChannel.phone ? TextInputType.phone : TextInputType.emailAddress,
              autofillHints: [_channel == OtpChannel.phone ? AutofillHints.telephoneNumber : AutofillHints.email],
              decoration: InputDecoration(
                labelText: _channel == OtpChannel.phone ? 'Mobile number' : 'Email',
                prefixText: _channel == OtpChannel.phone ? '+91 ' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  helperText: AppConfig.isDemo ? 'Demo mode: any 6 digits work' : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy
                  ? null
                  : !_codeSent
                      ? (_targetValid
                          ? () => _run(() async {
                                await backend.sendOtp(_channel, _normalizedTarget);
                                setState(() => _codeSent = true);
                              })
                          : null)
                      : (_code.text.length == 6
                          ? () => _run(() => backend.verifyOtp(_channel, _normalizedTarget, _code.text))
                          : null),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_codeSent ? 'Verify & continue' : 'Send code'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _codeSent = false;
                          _code.clear();
                        }),
                child: const Text('Use a different number / email'),
              ),
          ],
        ),
      ),
    );
  }
}
