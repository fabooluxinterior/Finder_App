"""Regenerates lib/core/phosphor.dart with only the Phosphor icons the app uses.

Usage: python3 tool/gen_icons.py <path to node_modules/@phosphor-icons/web>
(npm i @phosphor-icons/web@2.1.1). Fonts live in assets/fonts/Phosphor-*.ttf.
"""
import pathlib, re, sys

W = pathlib.Path(sys.argv[1])
used = {}
for f in pathlib.Path('lib').rglob('*.dart'):
    for style, name in re.findall(r'PhosphorIcons(Regular|Bold|Fill)\.(\w+)', f.read_text()):
        used.setdefault(style, set()).add(name)


def kebab(n):
    return re.sub(r'(?<=[a-z0-9])([A-Z])', r'-\1', n).lower()


css = {s: (W / f'src/{s.lower()}/style.css').read_text() for s in ['Regular', 'Bold', 'Fill']}
prefix = {'Regular': r'\.ph\.ph-', 'Bold': r'\.ph-bold\.ph-', 'Fill': r'\.ph-fill\.ph-'}
out = ["// GENERATED from @phosphor-icons/web 2.1.1 (MIT). Only the icons the app uses.",
       "// Regenerate with tool/gen_icons.py after adding icons.", "// ignore_for_file: constant_identifier_names", "",
       "import 'package:flutter/widgets.dart';", ""]
for style in ['Regular', 'Bold', 'Fill']:
    out.append(f"abstract final class PhosphorIcons{style} {{")
    for name in sorted(used.get(style, [])):
        m = re.search(prefix[style] + re.escape(kebab(name)) + r':before\s*\{\s*content:\s*"\\([0-9a-f]+)"', css[style])
        if not m:
            sys.exit(f'unknown icon: {style}.{name}')
        out.append(f"  static const IconData {name} = IconData(0x{m.group(1)}, fontFamily: 'Phosphor{style}');")
    out.append("}\n")
pathlib.Path('lib/core/phosphor.dart').write_text("\n".join(out))
