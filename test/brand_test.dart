import 'package:finder_app/core/brand.dart';
import 'package:finder_app/core/svg_path.dart';
import 'package:finder_app/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SVG path parser reproduces the logo bubble geometry', () {
    final p = VoubyPaths.bubble;
    // A circle of r≈24 around (32, 29) with a tail pointing down-left.
    expect(p.contains(const Offset(32, 29)), isTrue);
    expect(p.contains(const Offset(10, 29)), isTrue);
    expect(p.contains(const Offset(54, 29)), isTrue);
    expect(p.contains(const Offset(29, 59)), isTrue, reason: 'tail');
    expect(p.contains(const Offset(6, 29)), isFalse);
    expect(p.contains(const Offset(58, 29)), isFalse);
    expect(p.contains(const Offset(50, 58)), isFalse);
  });

  test('relative commands and implicit repeats', () {
    final p = parseSvgPath('M4 11l8-6.5 8 6.5V19a2 2 0 0 1-2 2h-3v-6h-6v6H6a2 2 0 0 1-2-2z');
    final b = p.getBounds();
    expect(b.left, closeTo(4, 0.01));
    expect(b.right, closeTo(20, 0.01));
    expect(b.top, closeTo(4.5, 0.01));
    expect(b.bottom, closeTo(21, 0.01));
  });

  testWidgets('opening animation plays and reports done', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(child: VoubySplash(onDone: () => done = true)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1800));
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
  });
}
