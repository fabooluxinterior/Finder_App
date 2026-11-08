import 'dart:ui';

import 'package:flutter/material.dart';
import 'phosphor.dart';

import '../data/memory_images.dart';
import 'feedback.dart';
import 'media_auth.dart';
import 'theme.dart';

/// Displays network URLs (authorised media function), bundled demo assets or
/// in-memory picks. Fades in instead of popping.
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({super.key, required this.url, required this.name, this.fit = BoxFit.cover, this.alignment = const Alignment(0, -0.2)});

  final String? url;
  final String name;
  final BoxFit fit;
  final Alignment alignment;

  Widget _fade(Widget child, int? frame, bool sync) => sync
      ? child
      : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.fast, curve: Motion.easeOut, child: child);

  @override
  Widget build(BuildContext context) {
    final u = url;
    final placeholder = _Initials(name: name);
    if (u == null || u.isEmpty) return placeholder;
    if (MemoryImages.isMemory(u)) {
      final bytes = MemoryImages.get(u);
      if (bytes == null) return placeholder;
      return Image.memory(bytes, fit: fit, alignment: alignment, gaplessPlayback: true);
    }
    if (u.startsWith('asset:')) {
      return Image.asset(u.substring(6), fit: fit, alignment: alignment, gaplessPlayback: true,
          frameBuilder: (c, child, f, s) => _fade(child, f, s), errorBuilder: (_, _, _) => placeholder);
    }
    return Image.network(
      u,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      headers: MediaAuth.isMediaUrl(u) ? MediaAuth.headers?.call() : null,
      frameBuilder: (c, child, f, s) => Stack(fit: StackFit.passthrough, children: [
        if (f == null) ColoredBox(color: context.fc.hair),
        _fade(child, f, s),
      ]),
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    return ColoredBox(
      color: c.hair,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(initials.toUpperCase(),
                style: TextStyle(color: c.muted, fontSize: 40, fontWeight: FontWeight.w600, letterSpacing: -1)),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, required this.name, this.size = 48, this.heroTag});
  final String? url;
  final String name;
  final double size;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final img = SizedBox.square(dimension: size, child: ClipOval(child: ProfilePhoto(url: url, name: name)));
    return heroTag == null ? img : Hero(tag: heroTag!, child: img);
  }
}

/// Every pressable thing shrinks slightly on touch-down (100–160 ms,
/// ease-out) so the UI feels like it's listening.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.96, this.haptic = true, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      enabled: widget.onTap != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) Fx.instance.tap();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Motion.of(context, Motion.press),
          curve: Motion.easeOut,
          child: AnimatedOpacity(
            opacity: widget.onTap == null ? 0.45 : 1,
            duration: Motion.fast,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Round icon button (✕, back, more…).
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 46,
    this.iconSize = 20,
    this.color,
    this.background,
    this.glass = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? background;
  final bool glass;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    Widget body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background ?? (glass ? Colors.white.withValues(alpha: 0.18) : c.surface),
        border: Border.all(color: glass ? Colors.white.withValues(alpha: 0.28) : c.hair),
        boxShadow: glass ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Icon(icon, size: iconSize, color: color ?? (glass ? Colors.white : c.ink)),
    );
    if (glass) {
      body = ClipOval(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: body));
    }
    return Pressable(onTap: onTap, semanticLabel: semanticLabel, child: body);
  }
}

/// Stadium button. [dark] = ink fill (primary); otherwise white with hairline.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    required this.onTap,
    this.dark = true,
    this.height = 54,
    this.expand = true,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final bool dark;
  final double height;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final fg = dark ? c.paper : c.ink;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
        if (trailingIcon != null) ...[const SizedBox(width: 8), Icon(trailingIcon, size: 17, color: fg)],
      ],
    );
    return Pressable(
      onTap: busy ? null : onTap,
      scale: 0.97,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: expand ? 20 : 18),
        decoration: BoxDecoration(
          color: dark ? c.ink : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: dark ? null : Border.all(color: c.hair),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.16 : 0.07), blurRadius: dark ? 18 : 12, offset: const Offset(0, 4)),
          ],
        ),
        child: AnimatedSwitcher(
          duration: Motion.fast,
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 20,
                  height: 20,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                )
              : KeyedSubtree(key: const ValueKey('content'), child: content),
        ),
      ),
    );
  }
}

/// Small gold "FAST-TRACK" tag.
class FastTrackBadge extends StatelessWidget {
  const FastTrackBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      height: 22,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(PhosphorIconsFill.lightning, size: 11, color: c.gold),
        if (!compact) ...[
          const SizedBox(width: 3),
          Text('FAST-TRACK', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: c.gold)),
        ],
      ]),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(PhosphorIconsFill.sealCheck, size: size, color: const Color(0xFF2E7CF6), semanticLabel: 'Verified');
}

/// Small rounded label with an icon (city, distance, privacy…).
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label, this.color, this.background});
  final IconData icon;
  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: background ?? c.surface,
        borderRadius: BorderRadius.circular(99),
        border: background == null ? Border.all(color: c.hair) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color ?? c.ink2),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color ?? c.ink2)),
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 8)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: context.fc.muted)),
      );
}

/// Progressive frosted fade (reference: milky glass over the photo bottom).
/// Stacked blur bands approximate a progressive blur cheaply; the colour
/// gradient on top carries the text contrast.
class FrostedFade extends StatelessWidget {
  const FrostedFade({super.key, required this.color, this.blur = true});
  final Color color;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      return Stack(fit: StackFit.expand, children: [
        if (blur)
          for (final (start, sigma) in [(0.44, 4.0), (0.60, 10.0), (0.76, 18.0)])
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h * (1 - start),
              child: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: const SizedBox.expand())),
            ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.28, 0.5, 1],
              colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.5), color.withValues(alpha: 0.84), color.withValues(alpha: 0.94)],
            ),
          ),
        ),
      ]);
    });
  }
}

/// Photo with a progressive frosted bottom: a blurred copy of the same
/// image is revealed through a gradient mask, then a milky colour wash
/// carries text contrast. One blur of the image, no backdrop filters, so it
/// renders identically everywhere and stays cheap while the card moves.
class FrostedPhoto extends StatelessWidget {
  const FrostedPhoto({super.key, required this.url, required this.name, required this.color, this.heroTag, this.blur = true});
  final String? url;
  final String name;
  final Color color;
  final Object? heroTag;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final photo = ProfilePhoto(url: url, name: name);
    return Stack(fit: StackFit.expand, children: [
      heroTag == null ? photo : Hero(tag: heroTag!, child: photo),
      if (blur)
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.5, 0.72],
            colors: [Colors.transparent, Colors.black],
          ).createShader(r),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
            child: ProfilePhoto(url: url, name: name),
          ),
        ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.48, 0.66, 0.8, 1],
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.55), color.withValues(alpha: 0.82), color.withValues(alpha: 0.92)],
          ),
        ),
      ),
    ]);
  }
}

void showSnack(BuildContext context, String text, {IconData? icon}) {
  final c = context.fc;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Row(children: [
        if (icon != null) ...[Icon(icon, color: c.paper, size: 18), const SizedBox(width: 10)],
        Expanded(child: Text(text)),
      ]),
    ));
}
