import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../core/phosphor.dart';
import '../../core/sanitizer.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../models/profile_catalog.dart';

/// Editable list of conversation prompts: question header, answer field with
/// a 150-character counter, and a writing tip under the prompt being edited.
class PromptListEditor extends StatefulWidget {
  const PromptListEditor({super.key, required this.prompts, required this.onChanged});
  final List<ProfilePrompt> prompts;
  final ValueChanged<List<ProfilePrompt>> onChanged;

  @override
  State<PromptListEditor> createState() => _PromptListEditorState();
}

class _PromptListEditorState extends State<PromptListEditor> {
  late List<ProfilePrompt> _items = [...widget.prompts];
  final _controllers = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};
  String? _active;

  TextEditingController _ctl(ProfilePrompt p) => _controllers.putIfAbsent(p.promptId, () {
    final c = TextEditingController(text: p.answer);
    c.addListener(() => _update(p.promptId, c.text));
    return c;
  });

  FocusNode _node(String id) => _focus.putIfAbsent(id, () {
    final f = FocusNode();
    f.addListener(() => setState(() => _active = f.hasFocus ? id : (_active == id ? null : _active)));
    return f;
  });

  @override
  void didUpdateWidget(PromptListEditor old) {
    super.didUpdateWidget(old);
    if (widget.prompts.map((p) => p.promptId).join() != _items.map((p) => p.promptId).join()) {
      _items = [...widget.prompts];
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _update(String id, String answer) {
    final i = _items.indexWhere((p) => p.promptId == id);
    if (i < 0 || _items[i].answer == answer) return;
    _items[i] = ProfilePrompt(promptId: id, question: _items[i].question, answer: answer);
    widget.onChanged([..._items]);
    setState(() {});
  }

  Future<void> _pick({ProfilePrompt? replacing}) async {
    final taken = {for (final p in _items) p.promptId};
    final picked = await showPromptPicker(context, exclude: taken..remove(replacing?.promptId));
    if (picked == null || !mounted) return;
    setState(() {
      final item = ProfilePrompt(promptId: picked.id, question: picked.question, answer: replacing?.answer ?? '');
      if (replacing != null) {
        final i = _items.indexOf(replacing);
        _controllers.remove(replacing.promptId)?.dispose();
        _items[i] = item;
      } else {
        _items.add(item);
      }
    });
    widget.onChanged([..._items]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _node(picked.id).requestFocus());
  }

  void _remove(ProfilePrompt p) {
    setState(() {
      _items.remove(p);
      _controllers.remove(p.promptId)?.dispose();
    });
    widget.onChanged([..._items]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in _items) ...[
          _PromptCard(
            prompt: p,
            controller: _ctl(p),
            focusNode: _node(p.promptId),
            active: _active == p.promptId,
            onChange: () => _pick(replacing: p),
            onRemove: () => _remove(p),
          ),
          const SizedBox(height: 12),
        ],
        if (_items.length < promptsMax)
          Pressable(
            onTap: _pick,
            semanticLabel: 'Add a prompt',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _items.length < promptsMin ? c.accent : c.hair),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  VIcon(VIcons.plus, size: 18, color: c.accent, stroke: 2.4),
                  const SizedBox(width: 8),
                  Text(
                    _items.length < promptsMin
                        ? 'Add a prompt (${_items.length}/$promptsMin required)'
                        : 'Add another prompt (optional)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.prompt,
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.onChange,
    required this.onRemove,
  });
  final ProfilePrompt prompt;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final def = promptById(prompt.promptId);
    final len = controller.text.trim().length;
    final contact = ContactSanitizer.containsContactInfo(controller.text);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: active ? c.ink3 : c.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  prompt.question,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink3),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Prompt options',
                color: c.surface,
                icon: VIcon(VIcons.more, size: 20, color: c.muted),
                onSelected: (v) => v == 'change' ? onChange() : onRemove(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'change', child: Text('Change question')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 2,
              maxLines: 4,
              maxLength: promptAnswerMax,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w500, color: c.ink),
              decoration: InputDecoration(
                hintText: 'Your answer',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.only(top: 8),
                counterText: '',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                if (contact)
                  Expanded(
                    child: Text(
                      'Remove phone numbers, handles or links.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFFFF6B5A)),
                    ),
                  )
                else
                  const Spacer(),
                Text(
                  '$len/$promptAnswerMax',
                  style: TextStyle(fontSize: 12.5, color: len > promptAnswerMax - 15 ? c.accent : c.muted),
                ),
              ],
            ),
          ),
          // Inline guidance under the prompt being written.
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.easeOut,
            child: active && def != null
                ? Container(
                    margin: const EdgeInsets.only(top: 10, right: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: c.goldSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(PhosphorIconsFill.lightbulb, size: 16, color: c.gold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(def.tip, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFFE9D3A8))),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Catalog picker grouped by category.
Future<PromptDef?> showPromptPicker(BuildContext context, {Set<String> exclude = const {}}) {
  return showModalBottomSheet<PromptDef>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final c = context.fc;
      final categories = <String, List<PromptDef>>{};
      for (final p in promptCatalog.where((p) => !exclude.contains(p.id))) {
        categories.putIfAbsent(p.category, () => []).add(p);
      }
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Pick a prompt',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.ink),
              ),
            ),
            for (final e in categories.entries) ...[
              SectionLabel(e.key, padding: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
              for (final p in e.value)
                Pressable(
                  scale: 0.98,
                  onTap: () => Navigator.pop(context, p),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.paper,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.hair),
                    ),
                    child: Text(
                      p.question,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.ink),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
