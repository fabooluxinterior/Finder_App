import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';

const _askedKey = 'push_asked';

/// Asks, in our own words, before Android's permission dialog appears. Shown
/// once; "Not now" switches popups off until the user turns them on in You.
/// When already answered, it just registers this phone quietly.
Future<void> askForPushOnce(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(pushEnabledProvider.notifier);
  bool asked = true;
  try {
    asked = (await SharedPreferences.getInstance()).getBool(_askedKey) ?? false;
  } catch (_) {}
  if (asked) {
    await notifier.start();
    return;
  }
  if (!ref.read(localNotifierProvider).available && !ref.read(pushServiceProvider).available) return;
  if (!context.mounted) return;
  final allow = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) {
      final c = ctx.fc;
      final t = Theme.of(ctx).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsFill.bell, size: 32, color: c.accent),
              const SizedBox(height: 14),
              Text('Turn on notifications?', style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Get a notification on your phone when someone messages you. '
                'You can change this any time in You → Popup notifications.',
                style: t.bodyMedium?.copyWith(color: c.ink2),
              ),
              const SizedBox(height: 20),
              PillButton(label: 'Allow notifications', onTap: () => Navigator.pop(ctx, true)),
              const SizedBox(height: 4),
              Center(
                child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              ),
            ],
          ),
        ),
      );
    },
  );
  try {
    await (await SharedPreferences.getInstance()).setBool(_askedKey, true);
  } catch (_) {}
  if (allow == true) {
    await ref.read(localNotifierProvider).requestPermission();
    await notifier.start();
  } else {
    await notifier.set(false);
  }
}
