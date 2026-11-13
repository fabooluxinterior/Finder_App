import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/feedback.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/security.dart';
import '../../providers.dart';

final verificationStatusProvider = FutureProvider<VerificationStatus>((ref) async {
  ref.watch(socialTickProvider);
  return ref.watch(backendProvider).verificationStatus();
});

/// Selfie verification: the server picks a random pose, the user takes a
/// live front-camera photo (no gallery), it goes through the secure upload
/// pipeline, and staff compare it with the profile photo.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  VerificationStart? _start;
  Uint8List? _selfie;
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } catch (e) {
      if (mounted) showSnack(context, '$e', icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _begin() => _run(() async {
    final s = await ref.read(backendProvider).startVerification();
    setState(() {
      _start = s;
      _selfie = null;
    });
  });

  Future<void> _capture() => _run(() async {
    final bytes = await ref.read(mediaProvider).takeSelfie();
    if (bytes != null) setState(() => _selfie = bytes);
  });

  Future<void> _submit() => _run(() async {
    await ref.read(backendProvider).submitVerificationSelfie(_start!.requestId, _selfie!);
    Fx.instance.unlock();
    ref.invalidate(verificationStatusProvider);
    setState(() {
      _start = null;
      _selfie = null;
    });
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final status = ref.watch(verificationStatusProvider).value ?? VerificationStatus.none;

    Widget body;
    if (status == VerificationStatus.approved) {
      body = _Message(
        leading: const VerifiedTick(size: 56),
        title: 'You’re verified',
        text: 'Your profile shows the blue Verified badge.',
      );
    } else if (status == VerificationStatus.pending) {
      body = _Message(
        icon: PhosphorIconsRegular.hourglass,
        title: 'Under review',
        text: AppConfig.isDemo
            ? 'Demo: approved automatically in a few seconds.'
            : 'Our team is comparing your selfie with your profile photo. This usually takes less than a day.',
      );
    } else if (_start == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status == VerificationStatus.rejected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(16)),
              child: Text(
                'Your last selfie couldn’t be matched to your profile photo. Make sure your face is clearly visible and try again.',
                style: t.bodySmall?.copyWith(color: c.ink),
              ),
            ),
          const VerifiedTick(size: 52),
          const SizedBox(height: 16),
          Text('Get the Verified badge', style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Take a quick selfie copying a pose we show you. Our team checks it matches your profile photo.',
            style: t.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: 18),
          for (final (icon, text) in [
            (PhosphorIconsRegular.camera, 'Live camera only. Gallery photos aren’t accepted.'),
            (PhosphorIconsRegular.eyeSlash, 'Your selfie is never shown on your profile.'),
            (PhosphorIconsRegular.trash, 'It’s deleted 30 days after review.'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: c.ink2),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: t.bodyMedium)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          PillButton(label: 'Start', busy: _busy, onTap: _begin),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Copy this pose', style: t.labelMedium?.copyWith(color: c.muted)),
          const SizedBox(height: 6),
          Text(_start!.pose, style: t.headlineSmall),
          const SizedBox(height: 18),
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _selfie == null
                  ? Container(
                      color: c.surface,
                      child: Icon(PhosphorIconsRegular.camera, size: 48, color: c.muted),
                    )
                  : Image.memory(_selfie!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 18),
          if (_selfie == null)
            PillButton(label: 'Take selfie', icon: PhosphorIconsFill.camera, busy: _busy, onTap: _capture)
          else
            Row(
              children: [
                Expanded(
                  child: PillButton(label: 'Retake', dark: false, onTap: _busy ? null : _capture),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(label: 'Submit', busy: _busy, onTap: _submit),
                ),
              ],
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIconsBold.caretLeft, color: c.ink),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text('Verification'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 8, 22, 24), child: body),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({this.icon, this.leading, required this.title, required this.text});
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          leading ?? Icon(icon, size: 52, color: context.fc.ink),
          const SizedBox(height: 16),
          Text(title, style: t.headlineSmall),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: context.fc.muted),
          ),
        ],
      ),
    );
  }
}
