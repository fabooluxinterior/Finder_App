import 'dart:ui';

/// Minimal SVG path-data parser (M L H V C S Q T A Z, absolute and relative),
/// so the brand mark and icons are drawn from the exact design source.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  var cx = 0.0, cy = 0.0; // last control point (for S/T)
  var prev = '';

  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double n() => double.parse(tokens[i++]);
  bool flag() {
    // Arc flags may be packed ("01" / "1.6"): take one digit.
    final t = tokens[i];
    if (t.length > 1 && (t.startsWith('0') || t.startsWith('1')) && !t.startsWith('0.') && !t.startsWith('1.')) {
      tokens[i] = t.substring(1);
      return t[0] == '1';
    }
    if (t.length > 1 && (t.startsWith('0.') || t.startsWith('1.'))) {
      tokens[i] = t.substring(1);
      return t[0] == '1';
    }
    i++;
    return t == '1';
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final nx = n(), ny = n();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.moveTo(x, y);
        sx = x;
        sy = y;
        cmd = rel ? 'l' : 'L';
        prev = 'M';
        continue;
      case 'L':
        final nx = n(), ny = n();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'H':
        final nx = n();
        x = rel ? x + nx : nx;
        path.lineTo(x, y);
      case 'V':
        final ny = n();
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'C':
        var x1 = n(), y1 = n(), x2 = n(), y2 = n(), nx = n(), ny = n();
        if (rel) {
          x1 += x;
          y1 += y;
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx = x2;
        cy = y2;
        x = nx;
        y = ny;
      case 'S':
        final x1 = 'CS'.contains(prev) ? 2 * x - cx : x, y1 = 'CS'.contains(prev) ? 2 * y - cy : y;
        var x2 = n(), y2 = n(), nx = n(), ny = n();
        if (rel) {
          x2 += x;
          y2 += y;
          nx += x;
          ny += y;
        }
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx = x2;
        cy = y2;
        x = nx;
        y = ny;
      case 'Q':
        var x1 = n(), y1 = n(), nx = n(), ny = n();
        if (rel) {
          x1 += x;
          y1 += y;
          nx += x;
          ny += y;
        }
        path.quadraticBezierTo(x1, y1, nx, ny);
        cx = x1;
        cy = y1;
        x = nx;
        y = ny;
      case 'T':
        final x1 = 'QT'.contains(prev) ? 2 * x - cx : x, y1 = 'QT'.contains(prev) ? 2 * y - cy : y;
        var nx = n(), ny = n();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.quadraticBezierTo(x1, y1, nx, ny);
        cx = x1;
        cy = y1;
        x = nx;
        y = ny;
      case 'A':
        final rx = n(), ry = n(), rot = n();
        final large = flag(), sweep = flag();
        var nx = n(), ny = n();
        if (rel) {
          nx += x;
          ny += y;
        }
        path.arcToPoint(Offset(nx, ny), radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        x = nx;
        y = ny;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
    }
    prev = cmd.toUpperCase();
  }
  return path;
}
