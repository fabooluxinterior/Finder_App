import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile_update.dart';
import '../../providers.dart';
import '../auth/add_email_screen.dart';
import '../profile/profile_editor_screen.dart';
import '../suggestions/discovery_preferences_screen.dart';

/// "Your profile needs a small update": shown to users who are missing a
/// detail introduced after launch. Appears at most once every 7 days per
/// detail (the server records when it was shown), can be put off with
/// "Not now", and optional details can be skipped for good. Never blocks the
/// app; "Complete profile" opens the editor at that field and saves only it.
class ProfileUpdateBanner extends ConsumerStatefulWidget {
  const ProfileUpdateBanner({super.key});

  @override
  ConsumerState<ProfileUpdateBanner> createState() => _ProfileUpdateBannerState();
}

class _ProfileUpdateBannerState extends ConsumerState<ProfileUpdateBanner> {
  /// Details shown in this session (kept visible until acted on, even though
  /// the server now says "recently shown").
  List<ProfileUpdate>? _shown;
  bool _closed = false;

  void _take(List<ProfileUpdate> updates) {
    if (_shown != null) return;
    final due = updates.where((u) => u.showPrompt).toList();
    if (due.isEmpty) return;
    _shown = due;
    final backend = ref.read(backendProvider);
    for (final u in due) {
      backend.markProfileUpdateSeen(u.key).catchError((_) {});
    }
  }

  Future<void> _complete(ProfileUpdate u) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => profileUpdateEditor(u)));
    ref.invalidate(profileUpdatesProvider);
  }

  Future<void> _skip(List<ProfileUpdate> items) async {
    setState(() => _closed = true);
    final backend = ref.read(backendProvider);
    for (final u in items.where((u) => u.optional)) {
      await backend.dismissProfileUpdate(u.key).catchError((_) {});
    }
    ref.invalidate(profileUpdatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(profileUpdatesProvider).value;
    if (updates != null) _take(updates);
    // Hide what's been completed meanwhile.
    final missing = {for (final u in updates ?? const <ProfileUpdate>[]) u.key};
    final items = (_shown ?? const <ProfileUpdate>[]).where((u) => missing.contains(u.key)).toList();
    final visible = !_closed && items.isNotEmpty;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: visible
          ? _Card(items: items, onComplete: _complete, onLater: () => setState(() => _closed = true), onSkip: _skip)
          : const SizedBox.shrink(),
    );
  }
}

/// The screen that completes one detail (and saves only that detail).
Widget profileUpdateEditor(ProfileUpdate u) => switch (u.form) {
  'discovery' => const DiscoveryPreferencesScreen(),
  'email' => const AddEmailScreen(),
  _ => ProfileEditorScreen(openField: u.key),
};

class _Card extends StatelessWidget {
  const _Card({required this.items, required this.onComplete, required this.onLater, required this.onSkip});
  final List<ProfileUpdate> items;
  final ValueChanged<ProfileUpdate> onComplete;
  final VoidCallback onLater;
  final ValueChanged<List<ProfileUpdate>> onSkip;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final first = items.first;
    final allOptional = items.every((u) => u.optional);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.hair),
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
                  child: Icon(PhosphorIconsFill.sparkle, size: 20, color: c.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your profile needs a small update',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items.length == 1
                            ? 'We’ve added a new profile detail: ${first.label}. ${first.description}'
                            : 'We’ve added new profile details: ${items.map((u) => u.label).join(', ')}.',
                        style: TextStyle(fontSize: 14, height: 1.35, color: c.ink2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Not now',
                  onPressed: onLater,
                  icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 30),
                PillButton(label: 'Complete profile', height: 42, expand: false, onTap: () => onComplete(first)),
                const SizedBox(width: 6),
                if (allOptional)
                  TextButton(
                    onPressed: () => onSkip(items),
                    child: Text('Don’t ask again', style: TextStyle(color: c.muted, fontSize: 13.5)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line for the You tab: "Profile completed" / "Additional information
/// required" / "Optional information available".
class ProfileUpdateStatusRow extends ConsumerWidget {
  const ProfileUpdateStatusRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fc;
    final updates = ref.watch(profileUpdatesProvider).value;
    if (updates == null) return const SizedBox.shrink();
    final (icon, color, text) = switch (summarizeUpdates(updates)) {
      ProfileUpdateSummary.complete => (PhosphorIconsFill.checkCircle, c.ok, 'Profile completed'),
      ProfileUpdateSummary.required => (PhosphorIconsFill.warningCircle, c.accent, 'Additional information required'),
      ProfileUpdateSummary.optional => (PhosphorIconsRegular.info, c.ink2, 'Optional information available'),
    };
    final tappable = updates.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: tappable
          ? () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => profileUpdateEditor(updates.first)));
              ref.invalidate(profileUpdatesProvider);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tappable ? '$text · ${updates.map((u) => u.label).join(', ')}' : text,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.ink2),
              ),
            ),
            if (tappable) Icon(PhosphorIconsRegular.caretRight, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}
