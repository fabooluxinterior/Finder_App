import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/backend.dart';
import '../../models/profile_catalog.dart' as catalog;
import '../../providers.dart';
import '../profile_builder/choice_sheet.dart' show TagChip;

/// Age range and who to show, used by Discover and Suggestions. Matching is
/// mutual: you only see people whose preferences include you too.
class DiscoveryPreferencesScreen extends ConsumerStatefulWidget {
  const DiscoveryPreferencesScreen({super.key});

  @override
  ConsumerState<DiscoveryPreferencesScreen> createState() => _DiscoveryPreferencesScreenState();
}

class _DiscoveryPreferencesScreenState extends ConsumerState<DiscoveryPreferencesScreen> {
  RangeValues? _ages;
  List<String>? _genders;
  bool _saving = false;

  Future<void> _save() async {
    final ages = _ages!;
    setState(() => _saving = true);
    try {
      await ref
          .read(backendProvider)
          .updateProfile(
            ProfilePatch({
              ProfilePatch.prefAgeMin: ages.start.round(),
              ProfilePatch.prefAgeMax: ages.end.round() >= 80 ? 99 : ages.end.round(),
              ProfilePatch.prefGenders: _genders!,
            }),
          );
      ref.invalidate(myProfileProvider);
      ref.invalidate(feedProvider);
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final me = ref.watch(myProfileProvider).value;
    if (me == null) return const Scaffold(body: SizedBox.shrink());
    final ages = _ages ??= RangeValues(me.prefAgeMin.toDouble(), me.prefAgeMax.clamp(18, 80).toDouble());
    final picked = _genders ??= [...me.prefGenders];
    return Scaffold(
      appBar: AppBar(title: const Text('Discovery preferences')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            'Used for Discover and Suggestions. It works both ways: people see you only if you fit their preferences too.',
            style: TextStyle(fontSize: 15, height: 1.45, color: c.ink3),
          ),
          const SectionLabel('Show me', padding: EdgeInsets.fromLTRB(2, 24, 2, 10)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TagChip(label: 'Everyone', selected: picked.isEmpty, onTap: () => setState(() => _genders = [])),
              for (final g in catalog.genders)
                TagChip(
                  label: g.label,
                  selected: picked.contains(g.value),
                  onTap: () => setState(() {
                    final next = [...picked];
                    next.contains(g.value) ? next.remove(g.value) : next.add(g.value);
                    _genders = next;
                  }),
                ),
            ],
          ),
          const SectionLabel('Age', padding: EdgeInsets.fromLTRB(2, 28, 2, 4)),
          Text(
            '${ages.start.round()} – ${ages.end.round() >= 80 ? '80+' : ages.end.round()}',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
          ),
          RangeSlider(
            values: ages,
            min: 18,
            max: 80,
            divisions: 62,
            activeColor: c.accent,
            inactiveColor: c.hair,
            labels: RangeLabels('${ages.start.round()}', '${ages.end.round()}'),
            onChanged: (v) => setState(() => _ages = v),
          ),
          const SizedBox(height: 28),
          PillButton(label: 'Save', height: 54, busy: _saving, onTap: _save),
        ],
      ),
    );
  }
}
