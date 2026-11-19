import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../providers.dart';

/// A friendly Malayalam / Manglish welcome for someone new, shown once (lines are edited from the web dashboard).
class FunWelcome extends ConsumerStatefulWidget {
  const FunWelcome({super.key});

  @override
  ConsumerState<FunWelcome> createState() => _FunWelcomeState();
}

class _FunWelcomeState extends ConsumerState<FunWelcome> {
  static const _key = 'fun_welcome_seen_v1';
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted && !(p.getBool(_key) ?? false)) setState(() => _show = true);
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    try {
      (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final c = context.fc;
    final lines = ref.watch(funLinesProvider).value;
    if (lines == null) return const SizedBox.shrink();
    return Dismissible(
      key: const ValueKey('fun-welcome'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _dismiss(),
      child: Material(
        color: c.surface,
        elevation: 3,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(lines.pick('welcome'), style: TextStyle(color: c.ink, fontSize: 14.5, height: 1.35)),
              ),
              IconButton(
                onPressed: _dismiss,
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
