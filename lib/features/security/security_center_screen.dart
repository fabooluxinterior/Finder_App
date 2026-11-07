import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/widgets.dart';
import '../../models/security.dart';
import '../../providers.dart';
import '../admin/admin_dashboard_screen.dart';
import 'mfa_screens.dart';

final _sessionsProvider = FutureProvider.autoDispose<List<SessionInfo>>((ref) => ref.watch(backendProvider).sessions());
final _devicesProvider = FutureProvider.autoDispose<List<DeviceInfo>>((ref) => ref.watch(backendProvider).devices());
final staffRoleProvider = FutureProvider<String?>((ref) async {
  ref.watch(authUserProvider);
  try {
    return await ref.watch(backendProvider).staffRole();
  } catch (_) {
    return null;
  }
});

class SecurityCenterScreen extends ConsumerWidget {
  const SecurityCenterScreen({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() body, String done) async {
    try {
      await body();
      if (context.mounted) showSnack(context, done);
    } on AppException catch (e) {
      if (!context.mounted) return;
      if (e.code == AppErrorCode.mfaRequired) {
        showSnack(context, 'Verify with your authenticator app first (sign out and back in).', icon: Icons.lock_outline);
      } else {
        showSnack(context, e.message, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final mfa = ref.watch(mfaStateProvider);
    final sessions = ref.watch(_sessionsProvider);
    final devices = ref.watch(_devicesProvider);
    final staff = ref.watch(staffRoleProvider).value;
    final fmt = DateFormat('d MMM, h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & security')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: Icon(backend.isEndToEndEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded),
            title: Text(backend.isEndToEndEncrypted ? 'Chats are end-to-end encrypted' : 'Demo mode: chats are not encrypted'),
            subtitle: Text(backend.isEndToEndEncrypted
                ? 'Messages and voice notes are encrypted on this device. Finder’s servers only store ciphertext they can’t read.'
                : 'The demo keeps sample messages in memory on this phone. The live app encrypts every chat end-to-end.'),
          ),
          if (kIsWeb)
            const ListTile(
              leading: Icon(Icons.info_outline, color: Colors.orange),
              title: Text('You’re using the web app'),
              subtitle: Text('Browsers have no hardware keystore and can’t block screenshots. Your keys are encrypted in this browser’s storage, '
                  'but the phone app protects them better. Don’t use the web app on shared computers, and sign out when you’re done.'),
            ),
          const Divider(),
          const _Header('Two-step verification'),
          mfa.when(
            loading: () => const ListTile(title: Text('Loading…')),
            error: (e, _) => ListTile(title: Text('$e')),
            data: (m) => m.enrolled
                ? ListTile(
                    leading: const Icon(Icons.verified_user, color: Colors.green),
                    title: const Text('On — authenticator app'),
                    subtitle: const Text('Needed when you sign in on a new device, add a device, or delete your account.'),
                    trailing: TextButton(
                      onPressed: () => _run(context, () async {
                        await backend.removeTotp(m.verifiedFactorIds.first);
                        ref.invalidate(mfaStateProvider);
                      }, 'Two-step verification turned off'),
                      child: const Text('Turn off'),
                    ),
                  )
                : ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: const Text('Off'),
                    subtitle: const Text('Protect your account with an authenticator app code.'),
                    trailing: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MfaEnrollScreen())),
                      child: const Text('Turn on'),
                    ),
                  ),
          ),
          const Divider(),
          const _Header('Devices with your encryption keys'),
          ...devices.when(
            loading: () => [const ListTile(title: Text('Loading…'))],
            error: (e, _) => [ListTile(title: Text('$e'))],
            data: (list) => [
              for (final d in list)
                ListTile(
                  leading: Icon(d.platform == 'web' ? Icons.language : Icons.smartphone),
                  title: Text(d.isThisDevice ? '${d.label} (this device)' : d.label),
                  subtitle: Text('Added ${fmt.format(d.createdAt)} · active ${fmt.format(d.lastSeen)}'),
                  trailing: d.isThisDevice
                      ? null
                      : IconButton(
                          tooltip: 'Remove device',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _run(context, () async {
                            await backend.revokeDevice(d.id);
                            ref.invalidate(_devicesProvider);
                          }, 'Device removed. It can’t decrypt new messages.'),
                        ),
                ),
            ],
          ),
          const Divider(),
          const _Header('Signed-in sessions'),
          ...sessions.when(
            loading: () => [const ListTile(title: Text('Loading…'))],
            error: (e, _) => [ListTile(title: Text('$e'))],
            data: (list) => [
              for (final s in list)
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(s.isCurrent ? 'This session' : (s.userAgent?.split(' ').first ?? 'Session')),
                  subtitle: Text('Signed in ${fmt.format(s.createdAt)}'
                      '${s.lastActive != null ? ' · active ${fmt.format(s.lastActive!)}' : ''}'
                      '${s.aal == 'aal2' ? ' · verified' : ''}'),
                  trailing: s.isCurrent
                      ? null
                      : IconButton(
                          tooltip: 'Sign out this session',
                          icon: const Icon(Icons.logout),
                          onPressed: () => _run(context, () async {
                            await backend.revokeSession(s.id);
                            ref.invalidate(_sessionsProvider);
                          }, 'Session signed out'),
                        ),
                ),
              ListTile(
                leading: const Icon(Icons.phonelink_erase_outlined),
                title: const Text('Sign out all other sessions'),
                onTap: () => _run(context, () async {
                  await backend.signOutOtherSessions();
                  ref.invalidate(_sessionsProvider);
                }, 'Other sessions signed out'),
              ),
            ],
          ),
          if (staff != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Safety & security dashboard'),
              subtitle: Text('Staff role: $staff'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen())),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Delete account', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Permanently deletes your profile, photos, keys and messages.'),
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'This removes your profile, photos, encryption keys, connections and server-side message data right away. '
                'Encrypted backups are overwritten within 7 days. Messages already on other people’s phones stay there.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
              onChanged: (_) => set(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(
              onPressed: ctl.text == 'DELETE' ? () => Navigator.pop(c, true) : null,
              child: const Text('Delete forever', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      await ref.read(backendProvider).deleteAccount();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }, 'Your account has been deleted');
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
      );
}
