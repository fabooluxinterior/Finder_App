import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';

import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/illustrations.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../providers.dart';
import '../legal/consent.dart';

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
  bool _agreed = SignupConsent.accepted;

  /// Seconds until "Resend code" works again (the sign-in service also limits
  /// how often a number can be texted).
  int _resendIn = 0;
  Timer? _tick;

  void _startCountdown() {
    _tick?.cancel();
    setState(() => _resendIn = 60);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 60));
      if (_resendIn == 0) t.cancel();
    });
  }

  void _resend() {
    if (_busy || _resendIn > 0) return;
    _run(() async {
      await ref.read(backendProvider).sendOtp(_channel, _normalizedTarget);
      _code.clear();
      _startCountdown();
      if (mounted) showSnack(context, 'New code sent.', icon: PhosphorIconsFill.checkCircle);
    });
  }

  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

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

  /// Shared by the Continue button and the keyboard's enter key.
  void _sendCode() {
    if (_busy) return;
    if (!_targetValid) {
      showSnack(context, _channel == OtpChannel.phone ? 'Enter a valid 10-digit mobile number.' : 'Enter a valid email address.');
      return;
    }
    if (!_agreed) {
      showSnack(context, 'Tick the box to confirm you’re 18+ and agree to the policies.');
      return;
    }
    _run(() async {
      await ref.read(backendProvider).sendOtp(_channel, _normalizedTarget);
      setState(() => _codeSent = true);
      _startCountdown();
    });
  }

  void _verify() {
    if (_busy || _code.text.length != 6) return;
    _run(() => ref.read(backendProvider).verifyOtp(_channel, _normalizedTarget, _code.text));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _target.dispose();
    _code.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    // While the keyboard is open the screen shrinks (resizeToAvoidBottomInset)
    // and the welcome art folds away, so the field and button sit right
    // above the keyboard. The page also scrolls if space is still tight.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 20),
              // A column with a minimum height (not IntrinsicHeight + Expanded):
              // fills the screen when there's room, scrolls when there isn't.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    // Welcome block keeps ~55% of the screen and centres in it.
                    constraints: BoxConstraints(minHeight: (box.maxHeight - 20) * (keyboardOpen ? 0.0 : 0.55)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSize(
                          duration: Motion.of(context, Motion.medium),
                          curve: Motion.easeOut,
                          alignment: Alignment.topLeft,
                          child: keyboardOpen
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 28, bottom: 36),
                                  child: _CardFan(animation: _intro),
                                ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: VoubyWordmark(size: keyboardOpen ? 36 : 56),
                        ),
                        // Folds away with the keyboard so the form stays in view.
                        AnimatedSize(
                          duration: Motion.of(context, Motion.medium),
                          curve: Motion.easeOut,
                          alignment: Alignment.topLeft,
                          child: keyboardOpen
                              ? const SizedBox(width: double.infinity)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      'Real people, real profiles. Chat when you both say hi.',
                                      style: TextStyle(
                                        fontSize: 30,
                                        height: 36 / 30,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.6,
                                        color: c.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Kochi · Kozhikode · Thiruvananthapuram',
                                      style: TextStyle(fontSize: 15, height: 22 / 15, color: c.muted),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_codeSent) ...[
                        _TargetField(
                          channel: _channel,
                          controller: _target,
                          onChanged: () => setState(() {}),
                          onSubmitted: _sendCode,
                        ),
                        const SizedBox(height: 12),
                        ConsentCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = SignupConsent.accepted = v)),
                        const SizedBox(height: 12),
                        PillButton(
                          label: 'Continue',
                          height: 58,
                          trailing: VIcon(VIcons.arrowRight, size: 20, color: c.paper),
                          busy: _busy,
                          // OTP can't be requested until the user is 18+ and has agreed.
                          onTap: _targetValid && _agreed ? _sendCode : null,
                        ),
                        // Mobile number only for new accounts; email sign-in stays
                        // for accounts created with an email before this change.
                        TextButton(
                          onPressed: () => setState(() {
                            _channel = _channel == OtpChannel.phone ? OtpChannel.email : OtpChannel.phone;
                            _target.clear();
                          }),
                          child: Text(
                            _channel == OtpChannel.phone ? 'Signed up with email? Sign in with email' : 'Use mobile number',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted),
                          ),
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
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: '••••••',
                            helperText: AppConfig.isDemo ? 'Demo: any 6 digits work' : null,
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: 10),
                        PillButton(label: 'Verify', height: 58, busy: _busy, onTap: _code.text.length == 6 ? _verify : null),
                        TextButton(
                          onPressed: _busy || _resendIn > 0 ? null : _resend,
                          child: Text(
                            _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
                            style: t.labelMedium?.copyWith(color: _resendIn > 0 ? c.muted : c.ink),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _codeSent = false;
                                  _code.clear();
                                  _tick?.cancel();
                                  _resendIn = 0;
                                }),
                          child: Text('Change number', style: t.labelMedium?.copyWith(color: c.ink2)),
                        ),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIconsFill.lockSimple, size: 13, color: c.muted),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'End-to-end encrypted chats · No screenshots',
                              textAlign: TextAlign.center,
                              style: t.bodySmall?.copyWith(color: c.muted),
                            ),
                          ),
                        ],
                      ),
                    ], // bottom group
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetField extends StatelessWidget {
  const _TargetField({required this.channel, required this.controller, required this.onChanged, required this.onSubmitted});
  final OtpChannel channel;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final phone = channel == OtpChannel.phone;
    return TextField(
      controller: controller,
      keyboardType: phone ? TextInputType.phone : TextInputType.emailAddress,
      autofillHints: [phone ? AutofillHints.telephoneNumberNational : AutofillHints.email],
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: c.ink),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
        hintText: phone ? 'Mobile number' : 'Email',
        prefixIcon: phone
            ? Padding(
                padding: const EdgeInsets.only(left: 20, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+91',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(width: 16),
                    Container(width: 1, height: 28, color: c.hair),
                  ],
                ),
              )
            : Icon(PhosphorIconsRegular.envelopeSimple, color: c.muted),
      ),
      // Enter / Go on the keyboard sends the code (same checks as the button).
      textInputAction: TextInputAction.go,
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Four tilted cards dealt in from the centre, then floating gently.
/// Demo builds show the bundled demo portraits; release builds show the
/// illustrated people (no real person is depicted).
class _CardFan extends StatefulWidget {
  const _CardFan({required this.animation});
  final Animation<double> animation;

  @override
  State<_CardFan> createState() => _CardFanState();
}

class _CardFanState extends State<_CardFan> with SingleTickerProviderStateMixin {
  static const _photos = [
    'assets/demo/p_meera.jpg',
    'assets/demo/p_arjun.jpg',
    'assets/demo/p_diya.jpg',
    'assets/demo/p_kiran.jpg',
  ];
  // left, top, rotation (deg), deal-in offset x
  static const _layout = [
    (0.0, 18.0, -8.0, 130.0),
    (86.0, 2.0, -3.0, 44.0),
    (172.0, 8.0, 3.0, -42.0),
    (254.0, 22.0, 9.0, -126.0),
  ];
  late final _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          // Fits 362 px of design width into whatever we have.
          final scale = (box.maxWidth / 362).clamp(0.6, 1.2);
          return SizedBox(
            height: 196 * scale,
            child: AnimatedBuilder(
              animation: Listenable.merge([widget.animation, _float]),
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < 4; i++)
                    Builder(
                      builder: (_) {
                        final (left, top, deg, dx) = _layout[i];
                        final start = 0.05 + i * 0.12;
                        final p = reduce
                            ? 1.0
                            : const Cubic(
                                0.2,
                                0.9,
                                0.25,
                                1.15,
                              ).transform(((widget.animation.value - start) / 0.6).clamp(0.0, 1.0));
                        final bob = reduce ? 0.0 : math.sin((_float.value + i * 0.12) * 2 * math.pi) * 3.5 - 3.5;
                        return Positioned(
                          left: left * scale,
                          top: top * scale,
                          child: Transform.translate(
                            offset: Offset(dx * (1 - p) * scale, 40 * (1 - p) * scale + bob),
                            child: Transform.rotate(
                              angle: deg * (2 * p - 1).clamp(-1.0, 1.0) * math.pi / 180,
                              child: Opacity(
                                opacity: p.clamp(0.0, 1.0),
                                child: Transform.scale(scale: 0.86 + 0.14 * p, child: _card(c, i, scale)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _card(FinderColors c, int i, double scale) => Container(
    width: 108 * scale,
    height: 140 * scale,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24 * scale),
      border: Border.all(color: c.paper, width: 3),
      boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 24, offset: Offset(0, 10))],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(21 * scale),
      child: AppConfig.isDemo
          ? Image.asset(_photos[i], fit: BoxFit.cover, alignment: const Alignment(0, -0.2), cacheWidth: 240)
          : IllustratedPerson(index: i),
    ),
  );
}
