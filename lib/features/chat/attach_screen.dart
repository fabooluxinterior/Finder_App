import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets.dart';
import 'attach_source.dart';

/// What the attach screen returns: the chosen pictures, or "use the system picker" when the phone refused access.
class AttachResult {
  const AttachResult.photos(this.photos) : useSystemPicker = false;
  const AttachResult.fallback() : photos = const [], useSystemPicker = true;
  final List<Uint8List> photos;
  final bool useSystemPicker;
}

const _accent = Color(0xFFFF5A3D);
const _maxPick = 10;

/// WhatsApp-style attach: the camera on top, your latest pictures in a row underneath; swipe the row up for the whole
/// gallery (tap to pick several); or take a picture with the round button.
class AttachScreen extends ConsumerStatefulWidget {
  const AttachScreen({super.key});

  @override
  ConsumerState<AttachScreen> createState() => _AttachScreenState();
}

class _AttachScreenState extends ConsumerState<AttachScreen> {
  late final AttachSource _src = ref.read(attachSourceProvider);
  bool _ready = false;
  bool _full = false;
  bool _busy = false;
  final _items = <GalleryItem>[];
  final _picked = <String>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  final _grid = ScrollController();

  @override
  void initState() {
    super.initState();
    _grid.addListener(() {
      if (_grid.hasClients && _grid.position.pixels > _grid.position.maxScrollExtent - 600) _loadMore();
    });
    _start();
  }

  @override
  void dispose() {
    _grid.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _src.init();
    if (!mounted) return;
    if (!ok) {
      Navigator.pop(context, const AttachResult.fallback());
      return;
    }
    setState(() => _ready = true);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_more || !_src.hasGallery) return;
    _loading = true;
    try {
      final next = await _src.recent(_page, 60);
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _page++;
        _more = next.length == 60;
      });
    } catch (_) {
      _more = false;
    } finally {
      _loading = false;
    }
  }

  Future<Uint8List?> _thumb(GalleryItem i) => _thumbs.putIfAbsent(i.id, () => _src.thumbnail(i, 240));

  Future<void> _finish(List<GalleryItem> chosen) async {
    if (_busy || chosen.isEmpty) return;
    setState(() => _busy = true);
    try {
      final out = <Uint8List>[];
      for (final i in chosen) {
        final b = await _src.original(i);
        if (b != null) out.add(b);
      }
      if (mounted) Navigator.pop(context, AttachResult.photos(out));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shoot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b = await _src.capture();
      if (!mounted) return;
      if (b == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context, AttachResult.photos([b]));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(GalleryItem i) => setState(() {
    if (_picked.contains(i.id)) {
      _picked.remove(i.id);
    } else if (_picked.length < _maxPick) {
      _picked.add(i.id);
    } else {
      showSnack(context, 'You can pick up to $_maxPick photos.');
    }
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final trayH = _full ? mq.size.height : 112.0 + mq.padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                // Camera
                Positioned.fill(
                  child: _src.hasCamera
                      ? _src.cameraPreview(context)
                      : const Center(
                          child: Text('Camera isn’t available', style: TextStyle(color: Colors.white54)),
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Round(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.pop(context)),
                        if (_src.hasCamera)
                          Row(
                            children: [
                              _Round(
                                icon: _src.flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                label: 'Flash',
                                onTap: () async {
                                  await _src.toggleFlash();
                                  if (mounted) setState(() {});
                                },
                              ),
                              if (_src.canFlip) ...[
                                const SizedBox(width: 8),
                                _Round(
                                  icon: Icons.flip_camera_android_rounded,
                                  label: 'Flip camera',
                                  onTap: () async {
                                    await _src.flip();
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (_src.hasCamera)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: trayH + 26,
                    child: Center(
                      child: Semantics(
                        button: true,
                        label: 'Take photo',
                        child: GestureDetector(
                          onTap: _shoot,
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: DecoratedBox(
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.white54 : Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Tray: a row of recent pictures; swipe up for the gallery.
                if (_src.hasGallery)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      height: trayH,
                      decoration: BoxDecoration(
                        color: const Color(0xF20B0B0C),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(_full ? 0 : 22)),
                      ),
                      child: GestureDetector(
                        // Swipe up anywhere on the row of pictures to open the whole gallery.
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragEnd: _full
                            ? null
                            : (d) {
                                if ((d.primaryVelocity ?? 0) < -150) setState(() => _full = true);
                              },
                        child: Column(
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragEnd: (d) {
                                final v = d.primaryVelocity ?? 0;
                                if (v < -150) setState(() => _full = true);
                                if (v > 150) setState(() => _full = false);
                              },
                              onTap: () => setState(() => _full = !_full),
                              child: Semantics(
                                button: true,
                                label: _full ? 'Show camera' : 'Show all photos',
                                child: SizedBox(
                                  height: 28,
                                  width: double.infinity,
                                  child: Center(
                                    child: Container(
                                      width: 38,
                                      height: 4,
                                      decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_full)
                              SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 14, 8),
                                  child: Row(
                                    children: [
                                      _Round(
                                        icon: Icons.arrow_back_rounded,
                                        label: 'Back',
                                        onTap: () => setState(() => _full = false),
                                      ),
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'Recent',
                                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Text(
                                        _picked.isEmpty ? 'Select' : '${_picked.length} selected',
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: _full
                                  ? GridView.builder(
                                      controller: _grid,
                                      padding: EdgeInsets.only(bottom: _picked.isEmpty ? 12 : 90),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        mainAxisSpacing: 2,
                                        crossAxisSpacing: 2,
                                      ),
                                      itemCount: _items.length,
                                      itemBuilder: (_, i) => _Tile(
                                        thumb: _thumb(_items[i]),
                                        order: _picked.indexOf(_items[i].id) + 1,
                                        selecting: true,
                                        onTap: () => _toggle(_items[i]),
                                      ),
                                    )
                                  : ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                                      itemCount: _items.length,
                                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                                      itemBuilder: (_, i) => SizedBox(
                                        width: 76,
                                        child: _Tile(thumb: _thumb(_items[i]), rounded: true, onTap: () => _finish([_items[i]])),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_full && _picked.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + mq.padding.bottom),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x000B0B0C), Color(0xFF0B0B0C)],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99)),
                            child: Text('${_picked.length} selected', style: const TextStyle(color: Colors.white)),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: const Color(0xFF0B0B0C),
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _finish([for (final id in _picked) _items.firstWhere((x) => x.id == id)]),
                            child: _busy
                                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Send', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 22)),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.thumb, required this.onTap, this.order = 0, this.selecting = false, this.rounded = false});
  final Future<Uint8List?> thumb;
  final VoidCallback onTap;
  final int order;
  final bool selecting;
  final bool rounded;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(rounded ? 10 : 0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: thumb,
            builder: (_, s) => s.data == null
                ? const ColoredBox(color: Color(0xFF1C1C1F))
                : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (selecting)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: order > 0 ? _accent : Colors.black38,
                  border: Border.all(color: order > 0 ? _accent : Colors.white, width: 2),
                ),
                child: order > 0
                    ? Text(
                        '$order',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0C)),
                      )
                    : null,
              ),
            ),
          if (selecting && order > 0) const ColoredBox(color: Color(0x33000000)),
        ],
      ),
    ),
  );
}
