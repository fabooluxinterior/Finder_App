import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';

enum Policy {
  terms('Terms of Service', 'TERMS_OF_SERVICE.md'),
  privacy('Privacy Policy', 'PRIVACY_POLICY.md'),
  guidelines('Community Guidelines', 'COMMUNITY_GUIDELINES.md');

  const Policy(this.title, this.asset);
  final String title;
  final String asset;

  static Policy? fromHref(String? href) {
    for (final p in values) {
      if (href != null && href.endsWith(p.asset)) return p;
    }
    return null;
  }
}

void openPolicy(BuildContext context, Policy policy) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PolicyScreen(policy: policy)));

/// Renders the same Markdown files that live in the repository root, so the
/// in-app text and the published policies can't drift apart.
class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.policy});
  final Policy policy;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIconsBold.caretLeft, color: c.ink),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(policy.title, style: t.titleLarge),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(policy.asset),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          // Drop the document's own H1; the app bar already shows the title.
          final body = policyForScreen(snap.data!);
          return Markdown(
            data: body,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            onTapLink: (text, href, title) {
              final target = Policy.fromHref(href);
              if (target != null && target != policy) openPolicy(context, target);
            },
            styleSheet: MarkdownStyleSheet(
              p: t.bodyMedium?.copyWith(color: c.ink2, height: 1.5),
              h2: t.titleLarge?.copyWith(height: 1.6),
              h3: t.titleMedium,
              strong: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
              a: TextStyle(color: c.ink, decoration: TextDecoration.underline),
              listBullet: t.bodyMedium?.copyWith(color: c.ink2),
              tableHead: t.labelMedium?.copyWith(color: c.ink),
              tableBody: t.bodySmall?.copyWith(color: c.ink2),
              tableBorder: TableBorder.all(color: c.hair),
              tableCellsPadding: const EdgeInsets.all(8),
              code: TextStyle(fontFamily: 'Geist', color: c.ink, backgroundColor: c.hair),
              blockSpacing: 12,
            ),
          );
        },
      ),
    );
  }
}

/// Prepares a policy Markdown file for a phone screen:
/// * `<FILL: …>` placeholders (still to be completed by the company) would
///   otherwise show as raw tag-like code; they become a readable marker.
/// * Wide tables become stacked blocks, one per row, instead of three
///   squeezed columns.
String policyForScreen(String md) {
  var s = md.replaceFirst(RegExp(r'^# .*\n'), '');
  s = s.replaceAllMapped(RegExp(r'<FILL:\s*([^>]+)>'), (m) => '*[${m[1]!.trim()} – to be added]*');
  // Any other angle-bracket tag-like text is shown literally, not as HTML.
  s = s.replaceAllMapped(RegExp(r'<(/?[A-Za-z][^>]*)>'), (m) => '‹${m[1]}›');

  final lines = s.split('\n');
  final out = <String>[];
  List<String> cells(String row) => row.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
  bool isSep(String row) => RegExp(r'^\s*\|?\s*:?-{2,}').hasMatch(row);
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.trimLeft().startsWith('|') && i + 1 < lines.length && isSep(lines[i + 1])) {
      final head = cells(l);
      i += 2;
      while (i < lines.length && lines[i].trimLeft().startsWith('|')) {
        final row = cells(lines[i]);
        out.add('- **${row.first}**  ');
        for (var k = 1; k < row.length && k < head.length; k++) {
          out.add('  ${head[k]}: ${row[k]}${k < row.length - 1 ? '  ' : ''}');
        }
        i++;
      }
      out.add('');
      i--;
      continue;
    }
    out.add(l);
  }
  return out.join('\n');
}
