import 'package:flutter/material.dart';

import '../data/memory_images.dart';
import 'theme.dart';

/// Displays network URLs, signed storage URLs, or demo `mem:` images,
/// with a gradient-initials fallback.
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({super.key, required this.url, required this.name, this.fit = BoxFit.cover});

  final String? url;
  final String name;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return _Initials(name: name);
    if (MemoryImages.isMemory(u)) {
      final bytes = MemoryImages.get(u);
      if (bytes == null) return _Initials(name: name);
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }
    if (u.startsWith('asset:')) {
      return Image.asset(u.substring(6), fit: fit, gaplessPlayback: true,
          errorBuilder: (_, _, _) => _Initials(name: name));
    }
    return Image.network(
      u,
      fit: fit,
      gaplessPlayback: true,
      loadingBuilder: (c, child, progress) =>
          progress == null ? child : Container(color: Colors.grey.shade200),
      errorBuilder: (_, _, _) => _Initials(name: name),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.url, required this.name, this.size = 48});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: ClipOval(child: ProfilePhoto(url: url, name: name)),
      );
}

class FastTrackBadge extends StatelessWidget {
  const FastTrackBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 3),
        decoration: BoxDecoration(gradient: AppColors.vipGradient, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_rounded, size: compact ? 12 : 14, color: Colors.white),
            if (!compact) ...[
              const SizedBox(width: 2),
              const Text('FAST-TRACK',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ],
          ],
        ),
      );
}

void showSnack(BuildContext context, String text, {IconData? icon}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Row(children: [
        if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 10)],
        Expanded(child: Text(text)),
      ]),
    ));
}
