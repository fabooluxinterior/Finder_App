import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/phosphor.dart';

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

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  OtpChannel _channel = OtpChannel.phone;
  final _target = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

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
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _code.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final backend = ref.read(backendProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PortraitFan(animation: _intro),
                    const SizedBox(height: 32),
                    const Wordmark(size: 44),
                    const SizedBox(height: 14),
                    Text('Private by default. Open only when you both say yes.',
                        style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 10),
                    Text('Kochi · Kozhikode · Thiruvananthapuram', style: t.bodyMedium?.copyWith(color: c.muted)),
                  ],
                ),
              ),
              if (!_codeSent) ...[
                _TargetField(
                  channel: _channel,
                  controller: _target,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                PillButton(
                  label: 'Continue',
                  trailingIcon: PhosphorIconsBold.arrowRight,
                  busy: _busy,
                  onTap: _targetValid
                      ? () => _run(() async {
                            await backend.sendOtp(_channel, _normalizedTarget);
                            setState(() => _codeSent = true);
                          })
                      : null,
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _channel = _channel == OtpChannel.phone ? OtpChannel.email : OtpChannel.phone;
                    _target.clear();
                  }),
                  child: Text(_channel == OtpChannel.phone ? 'Use email instead' : 'Use phone instead',
                      style: t.labelMedium?.copyWith(color: c.ink2)),
                ),
              ] else ...[
                Text('Enter the code sent to $_normalizedTarget', style: t.bodyMedium),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(letterSpacing: 12),
                  decoration: InputDecoration(
                    hintText: '••••••',
                    helperText: AppConfig.isDemo ? 'Demo: any 6 digits work' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                PillButton(
                  label: 'Verify',
                  busy: _busy,
                  onTap: _code.text.length == 6
                      ? () => _run(() => backend.verifyOtp(_channel, _normalizedTarget, _code.text))
                      : null,
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _codeSent = false;
                            _code.clear();
                          }),
                  child: Text('Change number', style: t.labelMedium?.copyWith(color: c.ink2)),
                ),
              ],
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(PhosphorIconsFill.lockSimple, size: 13, color: c.muted),
                const SizedBox(width: 5),
                Text('End-to-end encrypted chats · No screenshots', style: t.bodySmall?.copyWith(color: c.muted)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'finder'),
        TextSpan(text: '.', style: TextStyle(color: c.accent)),
      ]),
      style: TextStyle(fontFamily: 'Geist', fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -size * 0.04, color: c.ink),
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({required this.channel, required this.controller, required this.onChanged});
  final OtpChannel channel;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final phone = channel == OtpChannel.phone;
    return TextField(
      controller: controller,
      keyboardType: phone ? TextInputType.phone : TextInputType.emailAddress,
      autofillHints: [phone ? AutofillHints.telephoneNumberNational : AutofillHints.email],
      style: t.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: phone ? 'Mobile number' : 'Email',
        prefixIcon: phone
            ? Padding(
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('+91', style: t.titleMedium),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 22, color: c.hair),
                ]),
              )
            : Icon(PhosphorIconsRegular.envelopeSimple, color: c.muted),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

/// Four tilted portraits that slide up and settle once, on first view.
class _PortraitFan extends StatelessWidget {
  const _PortraitFan({required this.animation});
  final Animation<double> animation;

  static const _cards = [
    ('assets/demo/p_meera.jpg', -8.0, 6.0),
    ('assets/demo/p_arjun.jpg', -2.0, -4.0),
    ('assets/demo/p_diya.jpg', 5.0, 2.0),
    ('assets/demo/p_kiran.jpg', 10.0, 10.0),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox(
      height: 112,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < _cards.length; i++)
          AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final start = i * 0.06;
              final p = reduce ? 1.0 : Motion.easeOut.transform(((animation.value - start) / (1 - start)).clamp(0.0, 1.0));
              return Positioned(
                left: i * 58.0,
                top: _cards[i].$3 + (1 - p) * 24,
                child: Opacity(
                  opacity: p,
                  child: Transform.rotate(angle: _cards[i].$2 * 3.14159 / 180, child: child),
                ),
              );
            },
            child: Container(
              width: 76,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.paper, width: 3),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Image.asset(_cards[i].$1, fit: BoxFit.cover, alignment: const Alignment(0, 0.4)),
              ),
            ),
          ),
      ]),
    );
  }
}
