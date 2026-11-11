import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand.dart';
import '../../core/errors.dart';
import '../../core/image_optimizer.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../models/security.dart';
import '../../models/profile_catalog.dart';
import '../../providers.dart';

/// Six photo slots. Photos are optimised on this device (WebP, ≤1080 px,
/// <100 KB) before any upload. Long-press and drag to reorder; tap a photo to
/// replace or remove it (the old file is deleted from storage right away).
class PhotoGrid extends ConsumerStatefulWidget {
  const PhotoGrid({super.key});

  @override
  ConsumerState<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends ConsumerState<PhotoGrid> {
  /// Slot index -> status line while it's being processed.
  final _busy = <int, String>{};
  String? _lastResult;

  /// While any photo is "in review", ask again every few seconds so it flips to
  /// live by itself (no restart needed) and say so when it does.
  Timer? _poll;
  Set<String> _inReview = {};

  void _syncPolling(List<PhotoSlot> slots) {
    final pending = {
      for (final s in slots)
        if (s.pending) s.mediaId,
    };
    final approved = _inReview.where((id) => !pending.contains(id) && slots.any((s) => s.mediaId == id));
    if (approved.isNotEmpty) {
      ref.invalidate(myProfileProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showSnack(context, 'Photo approved', icon: PhosphorIconsFill.checkCircle);
      });
    }
    _inReview = pending;
    if (pending.isEmpty) {
      _poll?.cancel();
      _poll = null;
    } else {
      _poll ??= Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted) ref.invalidate(photoSlotsProvider);
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myProfileProvider);
    await ref.read(photoSlotsProvider.future);
  }

  Future<void> _add(int index, {PhotoSlot? replacing}) async {
    final media = ref.read(mediaProvider);
    final backend = ref.read(backendProvider);
    final original = await media.pickOriginalPhoto();
    if (original == null || !mounted) return;
    setState(() => _busy[index] = 'Optimising…');
    try {
      final optimized = await ImageOptimizer.optimize(original);
      if (!mounted) return;
      setState(() => _busy[index] = 'Uploading…');
      final status = await backend.uploadPhoto(optimized.bytes, mime: optimized.mime, replaces: replacing?.mediaId);
      _lastResult =
          '${(original.lengthInBytes / 1024).round()} KB → ${(optimized.bytes.lengthInBytes / 1024).round()} KB '
          '${optimized.mime == 'image/webp' ? 'WebP' : 'JPEG'}, ${optimized.width}×${optimized.height}';
      await _refresh();
      if (mounted && status == ImageUploadStatus.pending) {
        showSnack(
          context,
          'Photo added. It’s in review and will show up here by itself once it’s approved.',
          icon: PhosphorIconsFill.clock,
        );
      }
    } on ImageOptimizeException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy.remove(index));
    }
  }

  Future<void> _remove(int index, PhotoSlot slot) async {
    setState(() => _busy[index] = 'Removing…');
    try {
      await ref.read(backendProvider).removePhoto(slot.mediaId);
      await _refresh();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy.remove(index));
    }
  }

  Future<void> _move(List<PhotoSlot> slots, int from, int to) async {
    if (from == to) return;
    final order = [
      for (final s in slots)
        if (!s.pending) s.mediaId,
    ];
    if (from >= order.length || to >= order.length) return;
    final id = order.removeAt(from);
    order.insert(to, id);
    HapticFeedback.selectionClick();
    try {
      await ref.read(backendProvider).reorderPhotos(order);
      await _refresh();
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _menu(int index, PhotoSlot slot, int count) async {
    final c = context.fc;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index != 0 && !slot.pending)
                _SheetAction(icon: VIcons.done, label: 'Make main photo', onTap: () => Navigator.pop(context, 'main')),
              _SheetAction(icon: VIcons.photo, label: 'Replace photo', onTap: () => Navigator.pop(context, 'replace')),
              _SheetAction(
                icon: VIcons.close,
                label: 'Remove photo',
                color: const Color(0xFFFF6B5A),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              if (count <= photosMin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                  child: Text(
                    'Profiles need $photosMin photos to show in Discover.',
                    style: TextStyle(fontSize: 13, color: c.ink3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final slots = ref.read(photoSlotsProvider).value ?? const [];
    switch (action) {
      case 'main':
        await _move(slots, index, 0);
      case 'replace':
        await _add(index, replacing: slot);
      case 'remove':
        await _remove(index, slot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    ref.listen<AsyncValue<List<PhotoSlot>>>(photoSlotsProvider, (_, next) {
      final v = next.value;
      if (v != null) _syncPolling(v);
    });
    final slots = ref.watch(photoSlotsProvider).value ?? const <PhotoSlot>[];
    final live = slots.where((s) => !s.pending).length;
    final inReview = slots.length - live;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            const gap = 10.0;
            final w = (box.maxWidth - gap * 2) / 3;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < maxPhotoSlots; i++)
                  SizedBox(width: w, height: w * 1.28, child: _slot(context, i, i < slots.length ? slots[i] : null, slots, live)),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              live >= photosMin ? PhosphorIconsFill.checkCircle : PhosphorIconsRegular.info,
              size: 16,
              color: live >= photosMin ? c.ok : c.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                live >= photosMin
                    ? '$live of $maxPhotoSlots photos. Hold and drag to reorder.'
                    : 'Add ${photosMin - live} more (at least $photosMin). Hold and drag to reorder.',
                style: TextStyle(fontSize: 13.5, color: c.ink3),
              ),
            ),
          ],
        ),
        if (inReview > 0) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsFill.clock, size: 16, color: c.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$inReview in review. This updates by itself when ${inReview == 1 ? 'it’s' : 'they’re'} approved. '
                  'You can continue once at least $photosMin photos are approved.',
                  style: TextStyle(fontSize: 13.5, color: c.ink3),
                ),
              ),
            ],
          ),
        ],
        if (_lastResult != null) ...[
          const SizedBox(height: 4),
          Text('Last photo optimised on your phone: $_lastResult', style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      ],
    );
  }

  Widget _slot(BuildContext context, int i, PhotoSlot? slot, List<PhotoSlot> slots, int live) {
    final c = context.fc;
    final busy = _busy[i];
    final radius = BorderRadius.circular(20);

    if (slot == null) {
      final next = i == slots.length;
      return Semantics(
        button: true,
        label: 'Add photo ${i + 1}',
        child: Pressable(
          onTap: busy == null && next ? () => _add(i) : null,
          child: DottedSlot(
            highlighted: next,
            radius: 20,
            child: busy != null
                ? _BusyLabel(busy)
                : Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: next ? c.accent : c.hair, shape: BoxShape.circle),
                      child: Center(child: VIcon(VIcons.plus, size: 18, color: next ? c.paper : c.muted, stroke: 2.4)),
                    ),
                  ),
          ),
        ),
      );
    }

    final tile = ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ProfilePhoto(url: slot.url, name: '', decodeWidth: 360),
          if (slot.pending || busy != null)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: busy != null ? _BusyLabel(busy) : const _BusyLabel('In review', spinner: false),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(99)),
              child: Text(
                i == 0 ? 'Main' : '${i + 1}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );

    final tappable = Semantics(
      button: true,
      label: 'Photo ${i + 1}${slot.pending ? ', in review' : ''}. Options',
      child: Pressable(scale: 0.97, onTap: busy == null ? () => _menu(i, slot, live) : null, child: tile),
    );
    if (slot.pending) return tappable;

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => _move(slots, d.data, i),
      builder: (context, candidate, _) => AnimatedScale(
        scale: candidate.isNotEmpty ? 0.94 : 1,
        duration: Motion.of(context, Motion.fast),
        child: LongPressDraggable<int>(
          data: i,
          hapticFeedbackOnStart: true,
          feedback: LayoutBuilder(
            builder: (_, _) => SizedBox(width: 100, height: 128, child: Opacity(opacity: 0.9, child: tile)),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: tappable,
        ),
      ),
    );
  }
}

class _BusyLabel extends StatelessWidget {
  const _BusyLabel(this.text, {this.spinner = true});
  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spinner) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        if (spinner) const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ],
    ),
  );
}

/// Empty slot outline.
class DottedSlot extends StatelessWidget {
  const DottedSlot({super.key, required this.child, this.highlighted = false, this.radius = 20});
  final Widget child;
  final bool highlighted;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return CustomPaint(
      painter: _DashPainter(highlighted ? c.accent : c.hair, radius),
      child: Container(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(radius)),
        child: child,
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.label, required this.onTap, this.color});
  final String icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Pressable(
      scale: 0.98,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.hair),
        ),
        child: Row(
          children: [
            VIcon(icon, size: 20, color: color ?? c.ink),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: color ?? c.ink),
            ),
          ],
        ),
      ),
    );
  }
}
