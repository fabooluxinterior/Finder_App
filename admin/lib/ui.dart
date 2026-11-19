import 'package:flutter/material.dart';

const accent = Color(0xFFFF5A3D);
const okGreen = Color(0xFF3DDC84);
const warnAmber = Color(0xFFF5B83D);
const bg = Color(0xFF0B0B0C);
const surface = Color(0xFF161618);
const hair = Color(0xFF28282A);
const muted = Color(0xFF8A8A93);

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark, surface: surface, primary: accent);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: hair),
      ),
    ),
    dividerTheme: const DividerThemeData(color: hair, space: 1),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
  );
}

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Page scaffold: title, optional actions, scrollable body, max width.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 10,
                spacing: 10,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: const TextStyle(color: muted, fontSize: 14)),
                      ],
                    ],
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    ],
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.trailing, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: const TextStyle(color: muted, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: hair),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: muted, fontSize: 13)),
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
        Text(
          text,
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Loads data with a spinner / error + retry.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _f = widget.load();
  void _reload() => setState(() {
    _f = widget.load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _f,
    builder: (context, s) {
      if (s.hasError) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${s.error}', style: const TextStyle(color: muted)),
              ),
              TextButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        );
      }
      if (!s.hasData) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return widget.builder(context, s.data as T, _reload);
    },
  );
}

class MessagePage extends StatelessWidget {
  const MessagePage({super.key, required this.title, required this.body, this.action, this.onAction});
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.4),
              ),
              if (action != null) ...[const SizedBox(height: 20), FilledButton(onPressed: onAction, child: Text(action!))],
            ],
          ),
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
