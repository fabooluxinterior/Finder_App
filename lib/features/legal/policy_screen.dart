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
          final body = snap.data!.replaceFirst(RegExp(r'^# .*\n'), '');
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
