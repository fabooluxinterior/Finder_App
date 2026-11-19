import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

class _AttachScreenState extends ConsumerState<AttachScreen> with SingleTickerProviderStateMixin {
  late final AttachSource _src = ref.read(attachSourceProvider);
  // 0 = camera with a row of pictures, 1 = the whole gallery. Follows the finger while dragging, then settles.
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  bool _ready = false;
  bool _busy = false;
  final _items = <GalleryItem>[];
  final _picked = <String>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  bool _loaded = false;
  final _grid = ScrollController();
  List<GalleryAlbum> _albums = const [];
  GalleryAlbum? _album; // null = Recent (everything)

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
    _t.dispose();
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
      final next = await _src.recent(_page, 60, album: _album);
      if (!mounted) return;
      setState(() {
        _items.addAll(next);
        _page++;
        _more = next.length == 60;
        _loaded = true;
      });
    } catch (_) {
      _more = false;
      if (mounted) setState(() => _loaded = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _pickAlbum() async {
    if (_albums.isEmpty) _albums = await _src.albums();
    if (!mounted || _albums.isEmpty) return;
    final chosen = await showModalBottomSheet<GalleryAlbum>(
      context: context,
      backgroundColor: const Color(0xFF17171A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final a in _albums)
                ListTile(
                  title: Text(
                    a.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${a.count}', style: const TextStyle(color: Colors.white60)),
                  trailing: (_album?.id ?? _albums.first.id) == a.id ? const Icon(Icons.check, color: _accent) : null,
                  onTap: () => Navigator.pop(c, a),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _album = chosen == _albums.first ? null : chosen;
      _items.clear();
      _page = 0;
      _more = true;
      _loaded = false;
      _picked.clear();
    });
    if (_grid.hasClients) _grid.jumpTo(0);
    await _loadMore();
  }

  Future<void> _allowPhotos() async {
    final ok = await _src.requestGallery();
    if (!mounted) return;
    setState(() {});
    if (ok) await _loadMore();
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

  // ---- tray motion -------------------------------------------------------------------------------------------------
  double _range = 1;

  void _snap(double to, {double velocity = 0}) {
    _t.animateTo(
      to,
      curve: Curves.easeOutCubic,
      duration: Duration(milliseconds: 240 + (velocity.abs() > 1200 ? 0 : 60)),
    );
  }

  void _dragUpdate(DragUpdateDetails d) => _t.value = (_t.value - d.delta.dy / _range).clamp(0.0, 1.0);

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    _snap(v < -300 ? 1 : (v > 300 ? 0 : (_t.value > 0.5 ? 1 : 0)), velocity: v);
  }

  /// Pulling the grid down while it is at the top folds the tray back to the camera.
  bool _gridScroll(ScrollNotification n) {
    if (n is OverscrollNotification && n.overscroll < 0) {
      _t.value = (_t.value + n.overscroll / _range).clamp(0.0, 1.0);
    } else if (n is ScrollEndNotification && _t.value > 0 && _t.value < 1) {
      _snap(_t.value > 0.5 ? 1 : 0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final collapsed = 124.0 + mq.padding.bottom;
    _range = (mq.size.height - collapsed).clamp(1.0, 4000.0);
    return Scaffold(
      backgroundColor: Colors.black,
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final t = Curves.easeOut.transform(_t.value);
                final trayH = collapsed + (mq.size.height - collapsed) * _t.value;
                final camFade = (1 - _t.value * 2.4).clamp(0.0, 1.0);
                return Stack(
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
                    // Top bar: close on the left, flash on the right, clear of the status bar.
                    Positioned(
                      left: 16,
                      right: 16,
                      top: mq.padding.top + 14,
                      child: Opacity(
                        opacity: camFade,
                        child: IgnorePointer(
                          ignoring: camFade < 0.5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _Round(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.pop(context)),
                              if (_src.hasCamera)
                                _Round(
                                  icon: _src.flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                  label: 'Flash',
                                  onTap: () async {
                                    await _src.toggleFlash();
                                    if (mounted) setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Shutter in the middle; the camera switch at the right of it, just above the pictures.
                    if (_src.hasCamera)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: trayH + 22,
                        child: Opacity(
                          opacity: camFade,
                          child: IgnorePointer(
                            ignoring: camFade < 0.5,
                            child: SizedBox(
                              height: 76,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Semantics(
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
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _busy ? Colors.white54 : Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_src.canFlip)
                                    Positioned(
                                      right: 28,
                                      child: _Round(
                                        icon: Icons.flip_camera_android_rounded,
                                        label: 'Flip camera',
                                        size: 48,
                                        onTap: () async {
                                          await _src.flip();
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Tray: a row of recent pictures; drag it up for the gallery.
                    if (_src.hasGallery) _tray(mq, collapsed, trayH, t) else _allowTray(mq),
                    if (_picked.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: _t.value < 0.9,
                          child: Opacity(opacity: ((_t.value - 0.6) / 0.4).clamp(0.0, 1.0), child: _sendBar(mq)),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _allowTray(MediaQueryData mq) => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    child: Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + mq.padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xF20B0B0C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo_library_outlined, color: Colors.white70),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Allow photo access to see your pictures here.', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(onPressed: _allowPhotos, child: const Text('Allow')),
        ],
      ),
    ),
  );

  Widget _tray(MediaQueryData mq, double collapsed, double trayH, double t) {
    final stripOpacity = (1 - _t.value * 2.2).clamp(0.0, 1.0);
    final gridOpacity = ((_t.value - 0.25) / 0.6).clamp(0.0, 1.0);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: trayH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xF20B0B0C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22 * (1 - t))),
        ),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _dragUpdate,
              onVerticalDragEnd: _dragEnd,
              onTap: () => _snap(_t.value > 0.5 ? 0 : 1),
              child: Semantics(
                button: true,
                label: _t.value > 0.5 ? 'Show camera' : 'Show all photos',
                child: SizedBox(
                  height: 30,
                  width: double.infinity,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            if (_t.value > 0.02)
              Opacity(
                opacity: gridOpacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _dragUpdate,
                  onVerticalDragEnd: _dragEnd,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, mq.padding.top * _t.value, 14, 8),
                    child: Row(
                      children: [
                        _Round(icon: Icons.arrow_back_rounded, label: 'Back', onTap: () => _snap(0)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _pickAlbum,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _album?.name ?? 'Recent',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
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
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_t.value < 0.6)
                    Opacity(
                      opacity: stripOpacity,
                      child: IgnorePointer(
                        ignoring: _t.value > 0.1,
                        child: GestureDetector(onVerticalDragUpdate: _dragUpdate, onVerticalDragEnd: _dragEnd, child: _strip()),
                      ),
                    ),
                  if (_t.value > 0.02)
                    Opacity(
                      opacity: gridOpacity,
                      child: IgnorePointer(
                        ignoring: _t.value < 0.9,
                        child: NotificationListener<ScrollNotification>(onNotification: _gridScroll, child: _gridView()),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strip() {
    if (_items.isEmpty) {
      return Center(
        child: _loaded
            ? const Text('No pictures yet', style: TextStyle(color: Colors.white54))
            : const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) => SizedBox(
        width: 78,
        child: _Tile(thumb: _thumb(_items[i]), rounded: true, onTap: () => _finish([_items[i]])),
      ),
    );
  }

  /// The pictures in day groups, newest day first, each with a date heading (Today, Yesterday, Monday, 3 Nov, 3 Nov 2025).
  Widget _gridView() {
    final groups = <(String, List<GalleryItem>)>[];
    for (final i in _items) {
      final label = _dayLabel(i.takenAt);
      if (groups.isEmpty || groups.last.$1 != label) groups.add((label, []));
      groups.last.$2.add(i);
    }
    final dated = _items.any((i) => i.takenAt != null);
    return CustomScrollView(
      controller: _grid,
      slivers: [
        for (final g in groups) ...[
          if (dated)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Text(
                  g.$1,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate((_, k) {
              final it = g.$2[k];
              return _Tile(thumb: _thumb(it), order: _picked.indexOf(it.id) + 1, selecting: true, onTap: () => _toggle(it));
            }, childCount: g.$2.length),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: _picked.isEmpty ? 12 : 96)),
      ],
    );
  }

  static String _dayLabel(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(t);
    return DateFormat(t.year == now.year ? 'd MMM' : 'd MMM yyyy').format(t);
  }

  Widget _sendBar(MediaQueryData mq) => Container(
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
          onPressed: _busy ? null : () => _finish([for (final id in _picked) _items.firstWhere((x) => x.id == id)]),
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
    ),
  );
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onTap, this.size = 44});
  final double size;
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
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
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
                : Image.memory(
                    s.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                      opacity: frame == null && !sync ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      child: child,
                    ),
                  ),
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
