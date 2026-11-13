import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'app_update.dart';

/// "A new version is available". Opens the download; Android asks the user to
/// install it over the current app, which keeps their account and data.
/// Checks at launch and again when the app comes back (at most every 6 hours).
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> with WidgetsBindingObserver {
  bool _closed = false;
  int _dismissedBuild = 0; // "Not now" is remembered for that build, so it never nags again
  DateTime _checkedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance()
        .then((p) {
          if (mounted) setState(() => _dismissedBuild = p.getInt(_prefKey) ?? 0);
        })
        .catchError((_) {});
  }

  static const _prefKey = 'update_dismissed_build';

  Future<void> _dismiss(int build) async {
    setState(() {
      _closed = true;
      _dismissedBuild = build;
    });
    try {
      await (await SharedPreferences.getInstance()).setInt(_prefKey, build);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_checkedAt) > const Duration(hours: 6)) {
      _checkedAt = DateTime.now();
      ref.invalidate(availableUpdateProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(availableUpdateProvider).value;
    final visible = update != null && !_closed && update.build > _dismissedBuild;
    final c = context.fc;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !visible
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey(update.build),
              container: true,
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: c.accent.withValues(alpha: 0.5)),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(PhosphorIconsFill.downloadSimple, size: 20, color: c.accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A new version is available',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Download it and tap Install. Your account and chats on this phone are kept.',
                                style: TextStyle(fontSize: 14, height: 1.35, color: c.ink2),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Not now',
                          onPressed: () => _dismiss(update.build),
                          icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 30, top: 8),
                      child: PillButton(
                        label: 'Update',
                        height: 42,
                        expand: false,
                        onTap: () => launchUrl(update.url, mode: LaunchMode.externalApplication),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
