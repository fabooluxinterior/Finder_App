import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/profile_catalog.dart';
import 'choice_sheet.dart';

/// Categorised interest chips (min 5 during onboarding, max 15).
class InterestPicker extends StatelessWidget {
  const InterestPicker({super.key, required this.selected, required this.onChanged});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String tag) {
    final next = [...selected];
    if (next.contains(tag)) {
      next.remove(tag);
    } else if (next.length < interestsMax) {
      next.add(tag);
    } else {
      HapticFeedback.heavyImpact();
      return;
    }
    HapticFeedback.selectionClick();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final cat in interestCategories) ...[
          SectionLabel(cat.title, padding: const EdgeInsets.fromLTRB(2, 16, 2, 10)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in cat.tags) TagChip(label: t, selected: selected.contains(t), onTap: () => _toggle(t))],
          ),
        ],
      ],
    );
  }
}

/// "3 of 5 minimum" counter shown above the picker.
class InterestCounter extends StatelessWidget {
  const InterestCounter({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final ok = count >= interestsMin;
    return Text(
      ok ? '$count selected (up to $interestsMax)' : '$count of $interestsMin selected',
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ok ? c.ok : c.accent),
    );
  }
}
