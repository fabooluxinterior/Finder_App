import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';

/// The people you blocked. Unblocking removes the block only: the old connection and chat are not
/// restored, so the two of you would start again with a new request.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  final _busy = <String>{};

  Future<void> _unblock(BlockedUser u) async {
    setState(() => _busy.add(u.id));
    try {
      await ref.read(backendProvider).unblock(u.id);
      ref.invalidate(blockedUsersProvider);
      if (mounted) {
        showSnack(context, '${u.firstName} unblocked. Send a new request to connect again.', icon: PhosphorIconsFill.checkCircle);
      }
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final list = ref.watch(blockedUsersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('$e')),
        data: (users) => users.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsRegular.prohibit, size: 40, color: c.muted),
                      const SizedBox(height: 12),
                      Text('You haven’t blocked anyone.', style: TextStyle(color: c.muted, fontSize: 15)),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                    child: Text('They can’t see your profile or message you.', style: TextStyle(fontSize: 13, color: c.muted)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: c.hair),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < users.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 78, color: c.line),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: Row(
                              children: [
                                // A blocked person's photo is not available to you; initials stand in.
                                Avatar(url: null, name: users[i].fullName, size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        users[i].firstName,
                                        style: TextStyle(
                                          fontSize: 17,
                                          height: 22 / 17,
                                          fontWeight: FontWeight.w600,
                                          color: c.ink,
                                        ),
                                      ),
                                      if (users[i].city.isNotEmpty)
                                        Text(users[i].city, style: TextStyle(fontSize: 14.5, color: c.muted)),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 40,
                                  child: OutlinedButton(
                                    onPressed: _busy.contains(users[i].id) ? null : () => _unblock(users[i]),
                                    style: OutlinedButton.styleFrom(
                                      shape: const StadiumBorder(),
                                      side: BorderSide(color: c.hair),
                                      padding: const EdgeInsets.symmetric(horizontal: 18),
                                      foregroundColor: c.ink,
                                    ),
                                    child: _busy.contains(users[i].id)
                                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Unblock', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
