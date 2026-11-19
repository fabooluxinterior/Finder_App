import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/brand.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile_catalog.dart';

/// Bottom-sheet "drawer" for one structured choice. Returns the chosen value,
/// [cleared] when the user removes it, or null when dismissed.
const cleared = '\u0000clear';

Future<String?> showChoiceSheet(
  BuildContext context, {
  required String title,
  String? question,
  required List<Choice> choices,
  String? selected,
  bool allowClear = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final c = context.fc;
      return _SheetFrame(
        title: title,
        subtitle: question,
        body: Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              for (final ch in choices)
                _OptionRow(label: ch.label, selected: ch.value == selected, onTap: () => Navigator.pop(context, ch.value)),
              if (allowClear && selected != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, cleared),
                  child: Text('Remove from profile', style: TextStyle(color: c.ink3)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Multi-select drawer (languages). Returns the new selection or null.
Future<List<String>?> showMultiChoiceSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> options,
  required List<String> selected,
  required int max,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final picked = [...selected];
      return StatefulBuilder(
        builder: (context, setState) => _SheetFrame(
          title: title,
          subtitle: subtitle ?? 'Choose up to $max.',
          body: Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in options)
                    TagChip(
                      label: o,
                      selected: picked.contains(o),
                      onTap: () => setState(() {
                        if (picked.contains(o)) {
                          picked.remove(o);
                        } else if (picked.length < max) {
                          picked.add(o);
                        } else {
                          HapticFeedback.heavyImpact();
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          footer: PillButton(label: 'Done', onTap: () => Navigator.pop(context, picked)),
        ),
      );
    },
  );
}

/// Short free-text value (occupation, education). Returns trimmed text, ''
/// to clear, or null when dismissed.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String hint,
  String? initial,
  int maxLength = 60,
}) {
  final ctl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _SheetFrame(
        title: title,
        subtitle: 'No phone numbers, handles or links.',
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: ctl,
            autofocus: true,
            maxLength: maxLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        footer: PillButton(label: 'Save', onTap: () => Navigator.pop(context, ctl.text.trim())),
      ),
    ),
  );
}

/// Height in centimetres via a wheel.
Future<int?> showHeightSheet(BuildContext context, {int? initial}) {
  var value = initial ?? 165;
  return showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    builder: (context) {
      final c = context.fc;
      return _SheetFrame(
        title: 'Height',
        subtitle: 'Shown in centimetres.',
        body: SizedBox(
          height: 200,
          child: ListWheelScrollView.useDelegate(
            itemExtent: 44,
            physics: const FixedExtentScrollPhysics(),
            controller: FixedExtentScrollController(initialItem: value - 120),
            onSelectedItemChanged: (i) {
              value = 120 + i;
              HapticFeedback.selectionClick();
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: 111,
              builder: (_, i) => Center(
                child: Text(
                  '${120 + i} cm',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.ink),
                ),
              ),
            ),
          ),
        ),
        footer: PillButton(label: 'Save', onTap: () => Navigator.pop(context, value)),
      );
    },
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, this.subtitle, required this.body, this.footer});
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: c.hair, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.ink),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: TextStyle(fontSize: 15, height: 1.4, color: c.ink3)),
                ],
              ],
            ),
          ),
          body,
          if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: footer),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Pressable(
      scale: 0.98,
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.paper,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? c.accent : c.hair),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.ink),
              ),
            ),
            if (selected) VIcon(VIcons.done, size: 20, color: c.accent, stroke: 2.4),
          ],
        ),
      ),
    );
  }
}

/// Selectable pill used for interests and languages.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        scale: 0.95,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? c.accent : c.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? c.accent : c.hair),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: selected ? c.paper : c.ink),
          ),
        ),
      ),
    );
  }
}
