import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../models/follow_request.dart';
import '../../providers.dart';
import '../chats/chats_screen.dart' show PersonRow;
import '../chats/person_sheet.dart';

enum FollowTab { followers, following }

/// Followers (people who follow you) and Following (people you follow), each with its own list.
/// Both are private: only you ever see them.
class FollowListsScreen extends ConsumerStatefulWidget {
  const FollowListsScreen({super.key, this.initial = FollowTab.followers});
  final FollowTab initial;

  @override
  ConsumerState<FollowListsScreen> createState() => _FollowListsScreenState();
}

class _FollowListsScreenState extends ConsumerState<FollowListsScreen> {
  late FollowTab _tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final all = ref.watch(connectionsProvider).value ?? const <Connection>[];
    final followers = all.where((x) => x.followsMe).toList();
    final following = all.where((x) => x.iFollow).toList();
    final list = _tab == FollowTab.followers ? followers : following;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(_tab == FollowTab.followers ? 'Followers' : 'Following')),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 24),
        children: [
          _Segmented(
            tab: _tab,
            followers: followers.length,
            following: following.length,
            onChanged: (t) => setState(() => _tab = t),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Row(
              children: [
                Icon(PhosphorIconsFill.lockSimple, size: 13, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _tab == FollowTab.followers
                        ? 'People who follow you. Only you can see this.'
                        : 'People you follow. Only you can see this.',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: Motion.of(context, const Duration(milliseconds: 220)),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: list.isEmpty
                ? Padding(
                    key: ValueKey('empty-$_tab'),
                    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                    child: Text(
                      _tab == FollowTab.followers ? 'No followers yet.' : 'You aren’t following anyone yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.muted, fontSize: 15),
                    ),
                  )
                : Container(
                    key: ValueKey('list-$_tab'),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: c.hair),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 78, color: c.line),
                          PersonRow(
                            connection: list[i],
                            tag: list[i].isMutual ? 'Mutual' : '',
                            onTap: () => showPersonSheet(context, ref, list[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.tab, required this.followers, required this.following, required this.onChanged});
  final FollowTab tab;
  final int followers;
  final int following;
  final ValueChanged<FollowTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final dur = Motion.of(context, const Duration(milliseconds: 320));
    Widget item(FollowTab t, String label, int n) => Expanded(
      child: Semantics(
        button: true,
        selected: tab == t,
        label: '$label $n',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(t),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: dur,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: tab == t ? c.ink : c.muted),
              child: Text('$label $n'),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: c.hair),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: dur,
            curve: Curves.easeOutCubic,
            alignment: tab == FollowTab.followers ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Row(children: [item(FollowTab.followers, 'Followers', followers), item(FollowTab.following, 'Following', following)]),
        ],
      ),
    );
  }
}
