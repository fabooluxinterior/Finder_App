import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The full emoji keyboard: every emoji the phone can draw (smileys, people with skin tones, animals, food, travel,
/// activities, objects, symbols, flags), your recent ones, and search. Taps insert at the cursor of the message box.
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.onPick, required this.onBackspace});
  final ValueChanged<String> onPick;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hair)),
      ),
      child: EmojiPicker(
        onEmojiSelected: (_, e) => onPick(e.emoji),
        onBackspacePressed: onBackspace,
        config: Config(
          height: 300,
          emojiTextStyle: const TextStyle(fontSize: 26),
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 30,
            backgroundColor: c.surface,
            recentsLimit: 32,
            noRecents: Text('No recent emoji yet', style: TextStyle(color: c.ink2)),
          ),
          skinToneConfig: const SkinToneConfig(),
          categoryViewConfig: CategoryViewConfig(
            initCategory: Category.SMILEYS,
            backgroundColor: c.surface,
            indicatorColor: c.accent,
            iconColor: c.ink2,
            iconColorSelected: c.accent,
            backspaceColor: c.accent,
            dividerColor: c.hair,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: c.surface,
            buttonColor: c.surface,
            buttonIconColor: c.ink2,
          ),
          searchViewConfig: SearchViewConfig(backgroundColor: c.surface, buttonIconColor: c.ink2, hintText: 'Search emoji'),
        ),
      ),
    );
  }
}
