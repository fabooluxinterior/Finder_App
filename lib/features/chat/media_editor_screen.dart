import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/phosphor.dart';
import '../../core/view_once_icon.dart';
import 'schedule_picker.dart';

/// What the editor hands back: the finished picture and, when "send later" was used, when to send it.
class EditedMedia {
  const EditedMedia(this.bytes, {this.sendAt, this.once = false});
  final Uint8List bytes;
  final DateTime? sendAt;

  /// "View once": the other person can open it a single time.
  final bool once;
}

class _Stroke {
  _Stroke(this.color, this.width) : points = [];
  final Color color;
  final double width; // fraction of the picture width
  final List<Offset> points; // fractions of the picture size
}

class _Label {
  _Label(this.text, this.color, this.pos);
  String text;
  Color color;
  Offset pos; // centre, as a fraction of the picture size
}

enum _Tool { none, draw, text, crop }

const _palette = [
  Colors.white,
  Colors.black,
  Color(0xFFFF4D4D),
  Color(0xFFFFC53D),
  Color(0xFF3DDC84),
  Color(0xFF3D9BFF),
  Color(0xFFB45CFF),
];

/// A full-screen preview of the chosen picture before it is sent: draw with a pencil, add text, crop, then send once.
class MediaEditorScreen extends StatefulWidget {
  const MediaEditorScreen({super.key, required this.bytes, this.allowSchedule = true, this.allowOnce = true, this.positionLabel});
  final Uint8List bytes;
  final bool allowSchedule;

  /// "View once" is only offered for a single photo.
  final bool allowOnce;

  /// "2 of 3" when several photos are being sent.
  final String? positionLabel;

  @override
  State<MediaEditorScreen> createState() => _MediaEditorScreenState();
}

class _MediaEditorScreenState extends State<MediaEditorScreen> {
  ui.Image? _image;
  var _tool = _Tool.none;
  Color _color = Colors.white;
  final _strokes = <_Stroke>[];
  final _labels = <_Label>[];
  _Stroke? _current;
  Rect _crop = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
  bool _busy = false;
  bool _once = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _decode(widget.bytes);
  }

  Future<void> _decode(Uint8List bytes) async {
    try {
      final img = await decodeImageFromList(bytes);
      if (mounted) setState(() => _image = img);
    } catch (_) {
      if (mounted) setState(() => _error = 'This picture can’t be opened.');
    }
  }

  double get _aspect => _image == null ? 1 : _image!.width / _image!.height;

  // ------------------------------------------------------------- drawing ----
  void _undo() => setState(() {
    if (_labels.isNotEmpty && (_strokes.isEmpty || _lastWasLabel)) {
      _labels.removeLast();
    } else if (_strokes.isNotEmpty) {
      _strokes.removeLast();
    }
  });

  bool _lastWasLabel = false;

  Future<String?> _askText(String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add text'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 80, minLines: 1, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _addText() async {
    final t = await _askText('');
    if (t == null || t.isEmpty || !mounted) return;
    setState(() {
      _labels.add(_Label(t, _color, const Offset(0.5, 0.5)));
      _lastWasLabel = true;
      _tool = _Tool.none;
    });
  }

  // ---------------------------------------------------------------- crop ----
  Future<void> _applyCrop() async {
    final img = _image;
    if (img == null) return;
    final r = _crop;
    final w = (img.width * r.width).round().clamp(16, img.width);
    final h = (img.height * r.height).round().clamp(16, img.height);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(img.width * r.left, img.height * r.top, img.width * r.width, img.height * r.height),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final cropped = await rec.endRecording().toImage(w, h);
    Offset map(Offset p) => Offset((p.dx - r.left) / r.width, (p.dy - r.top) / r.height);
    setState(() {
      // Drawings and text keep their place on the picture.
      for (final s in _strokes) {
        for (var i = 0; i < s.points.length; i++) {
          s.points[i] = map(s.points[i]);
        }
      }
      for (final l in _labels) {
        l.pos = map(l.pos);
      }
      _image = cropped;
      _crop = const Rect.fromLTWH(0.05, 0.05, 0.9, 0.9);
      _tool = _Tool.none;
    });
  }

  // -------------------------------------------------------------- export ----
  Future<Uint8List> _render() async {
    final img = _image!;
    final scale = math.min(1.0, 1600 / math.max(img.width, img.height));
    final w = (img.width * scale).round(), h = (img.height * scale).round();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    _paintOverlays(canvas, Size(w.toDouble(), h.toDouble()));
    final out = await rec.endRecording().toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  void _paintOverlays(Canvas canvas, Size size) {
    for (final s in _strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.width * size.width;
      if (s.points.length == 1) {
        canvas.drawCircle(
          Offset(s.points.first.dx * size.width, s.points.first.dy * size.height),
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
        continue;
      }
      final path = Path()..moveTo(s.points.first.dx * size.width, s.points.first.dy * size.height);
      for (final p in s.points.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
    for (final l in _labels) {
      final tp = TextPainter(
        text: TextSpan(
          text: l.text,
          style: TextStyle(
            color: l.color,
            fontSize: size.width * 0.07,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width * 0.9);
      tp.paint(canvas, Offset(l.pos.dx * size.width - tp.width / 2, l.pos.dy * size.height - tp.height / 2));
    }
  }

  Future<void> _send({bool later = false}) async {
    if (_busy || _image == null) return;
    DateTime? at;
    if (later) {
      at = await pickSendTime(context);
      if (at == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await _render();
      if (mounted) Navigator.pop(context, EditedMedia(bytes, sendAt: at, once: widget.allowOnce && _once));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ UI ----
  @override
  Widget build(BuildContext context) {
    const bg = Colors.black;
    if (_error != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, foregroundColor: Colors.white),
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  _ToolButton(
                    icon: Icons.crop,
                    label: 'Crop',
                    on: _tool == _Tool.crop,
                    onTap: () => setState(() => _tool = _tool == _Tool.crop ? _Tool.none : _Tool.crop),
                  ),
                  _ToolButton(icon: Icons.text_fields, label: 'Text', on: _tool == _Tool.text, onTap: _addText),
                  _ToolButton(
                    icon: Icons.edit,
                    label: 'Pencil',
                    on: _tool == _Tool.draw,
                    onTap: () => setState(() => _tool = _tool == _Tool.draw ? _Tool.none : _Tool.draw),
                  ),
                  IconButton(
                    onPressed: _strokes.isEmpty && _labels.isEmpty ? null : _undo,
                    tooltip: 'Undo',
                    icon: Icon(Icons.undo, color: _strokes.isEmpty && _labels.isEmpty ? Colors.white30 : Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, box) {
                        // The picture, fitted inside the free space.
                        var w = box.maxWidth, h = w / _aspect;
                        if (h > box.maxHeight) {
                          h = box.maxHeight;
                          w = h * _aspect;
                        }
                        final size = Size(w, h);
                        return Center(
                          child: SizedBox(
                            width: w,
                            height: h,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _tool == _Tool.draw
                                  ? (d) => setState(() {
                                      _current = _Stroke(_color, 0.012)..points.add(_frac(d.localPosition, size));
                                      _strokes.add(_current!);
                                      _lastWasLabel = false;
                                    })
                                  : null,
                              onPanUpdate: _tool == _Tool.draw
                                  ? (d) => setState(() => _current?.points.add(_frac(d.localPosition, size)))
                                  : null,
                              onPanEnd: _tool == _Tool.draw ? (_) => _current = null : null,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  RawImage(image: _image, fit: BoxFit.fill),
                                  CustomPaint(painter: _OverlayPainter(this)),
                                  if (_tool != _Tool.crop)
                                    for (final l in _labels)
                                      Positioned(
                                        left: l.pos.dx * w - 80,
                                        top: l.pos.dy * h - 20,
                                        width: 160,
                                        height: 40,
                                        child: GestureDetector(
                                          onPanUpdate: (d) => setState(
                                            () => l.pos = Offset(
                                              (l.pos.dx + d.delta.dx / w).clamp(0.0, 1.0),
                                              (l.pos.dy + d.delta.dy / h).clamp(0.0, 1.0),
                                            ),
                                          ),
                                          onTap: () async {
                                            final t = await _askText(l.text);
                                            if (t != null && t.isNotEmpty) setState(() => l.text = t);
                                          },
                                          onLongPress: () => setState(() => _labels.remove(l)),
                                          child: const SizedBox.expand(),
                                        ),
                                      ),
                                  if (_tool == _Tool.crop)
                                    _CropOverlay(rect: _crop, size: size, onChanged: (r) => setState(() => _crop = r)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_tool == _Tool.draw || _tool == _Tool.text)
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final col in _palette)
                      GestureDetector(
                        onTap: () => setState(() => _color = col),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == col ? Colors.white : Colors.white24,
                              width: _color == col ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: _tool == _Tool.crop
                  ? Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _tool = _Tool.none),
                          child: const Text('Cancel crop', style: TextStyle(color: Colors.white)),
                        ),
                        const Spacer(),
                        FilledButton(onPressed: _applyCrop, child: const Text('Apply crop')),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: widget.positionLabel == null
                                ? null
                                : Text(widget.positionLabel!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          ),
                        ),
                        if (widget.allowOnce)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Semantics(
                              button: true,
                              toggled: _once,
                              label: 'View once',
                              child: Tooltip(
                                message: 'View once',
                                child: InkResponse(
                                  onTap: () => setState(() => _once = !_once),
                                  radius: 26,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _once ? Colors.white24 : Colors.transparent,
                                    ),
                                    child: ViewOnceIcon(size: 28, color: Colors.white, filled: _once),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        GestureDetector(
                          onLongPress: widget.allowSchedule ? () => _send(later: true) : null,
                          child: Tooltip(
                            message: widget.allowSchedule ? 'Send (hold to send later)' : 'Send',
                            child: Material(
                              color: const Color(0xFFFF5A3D),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _busy ? null : _send,
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: _busy
                                      ? const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(PhosphorIconsFill.paperPlaneTilt, color: Colors.white),
                                ),
                              ),
                            ),
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

  Offset _frac(Offset p, Size s) => Offset((p.dx / s.width).clamp(0.0, 1.0), (p.dy / s.height).clamp(0.0, 1.0));
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.state) : super(repaint: null);
  final _MediaEditorScreenState state;

  @override
  void paint(Canvas canvas, Size size) => state._paintOverlays(canvas, size);

  @override
  bool shouldRepaint(covariant _OverlayPainter old) => true;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: label,
    icon: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: on ? const Color(0xFFFF5A3D) : Colors.transparent, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );
}

/// A rectangle with draggable corners and a draggable body, in fractions of the picture.
class _CropOverlay extends StatelessWidget {
  const _CropOverlay({required this.rect, required this.size, required this.onChanged});
  final Rect rect;
  final Size size;
  final ValueChanged<Rect> onChanged;

  static const _min = 0.12;

  Rect _fix(Rect r) {
    var l = r.left.clamp(0.0, 1.0 - _min), t = r.top.clamp(0.0, 1.0 - _min);
    var rr = r.right.clamp(l + _min, 1.0), b = r.bottom.clamp(t + _min, 1.0);
    return Rect.fromLTRB(l, t, rr, b);
  }

  @override
  Widget build(BuildContext context) {
    final px = Rect.fromLTRB(rect.left * size.width, rect.top * size.height, rect.right * size.width, rect.bottom * size.height);
    Widget handle(Alignment a, void Function(Offset d) move) => Positioned(
      left: px.left + (a.x + 1) / 2 * px.width - 22,
      top: px.top + (a.y + 1) / 2 * px.height - 22,
      width: 44,
      height: 44,
      child: GestureDetector(
        onPanUpdate: (d) => move(Offset(d.delta.dx / size.width, d.delta.dy / size.height)),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black54),
            ),
          ),
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: CustomPaint(painter: _DimPainter(px))),
        Positioned.fromRect(
          rect: px,
          child: GestureDetector(
            onPanUpdate: (d) {
              final dx = d.delta.dx / size.width, dy = d.delta.dy / size.height;
              final moved = rect.shift(Offset(dx, dy));
              final shift = Offset(
                moved.left < 0 ? -moved.left : (moved.right > 1 ? 1 - moved.right : 0),
                moved.top < 0 ? -moved.top : (moved.bottom > 1 ? 1 - moved.bottom : 0),
              );
              onChanged(moved.shift(shift));
            },
            child: const SizedBox.expand(),
          ),
        ),
        handle(
          Alignment.topLeft,
          (d) => onChanged(_fix(Rect.fromLTRB(rect.left + d.dx, rect.top + d.dy, rect.right, rect.bottom))),
        ),
        handle(
          Alignment.topRight,
          (d) => onChanged(_fix(Rect.fromLTRB(rect.left, rect.top + d.dy, rect.right + d.dx, rect.bottom))),
        ),
        handle(
          Alignment.bottomLeft,
          (d) => onChanged(_fix(Rect.fromLTRB(rect.left + d.dx, rect.top, rect.right, rect.bottom + d.dy))),
        ),
        handle(
          Alignment.bottomRight,
          (d) => onChanged(_fix(Rect.fromLTRB(rect.left, rect.top, rect.right + d.dx, rect.bottom + d.dy))),
        ),
      ],
    );
  }
}

class _DimPainter extends CustomPainter {
  _DimPainter(this.hole);
  final Rect hole;
  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black54);
    canvas.drawRect(
      hole,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _DimPainter old) => old.hole != hole;
}
