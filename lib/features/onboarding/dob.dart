import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config.dart';
import '../../core/errors.dart';
import '../../core/phosphor.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../providers.dart';
import '../legal/consent.dart';

int ageOn(DateTime dob, [DateTime? today]) {
  final now = today ?? DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
  return age;
}

/// Latest date of birth that is still 18+ today.
DateTime latestAdultDob([DateTime? today]) {
  final now = today ?? DateTime.now();
  final candidate = DateTime(now.year - AppConfig.minimumAge, now.month, now.day);
  // 29 Feb birthdays in non-leap target years roll back to 28 Feb.
  return candidate.month == now.month ? candidate : DateTime(now.year - AppConfig.minimumAge, now.month + 1, 0);
}

/// Tappable date-of-birth field. The picker can't select anything under 18;
/// the server enforces the same rule.
class DobField extends StatelessWidget {
  const DobField({super.key, required this.value, required this.onChanged});
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  Future<void> _pick(BuildContext context) async {
    final last = latestAdultDob();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime(last.year - 6, last.month, 1),
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: last,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Your date of birth',
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    final v = value;
    return Pressable(
      scale: 0.99,
      onTap: () => _pick(context),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.hair),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.cake, size: 20, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                v == null ? 'Date of birth' : DateFormat('d MMMM yyyy').format(v),
                style: v == null ? t.bodyLarge?.copyWith(color: c.muted) : t.titleMedium,
              ),
            ),
            if (v != null) Text('${ageOn(v)} yrs', style: t.labelMedium?.copyWith(color: c.muted)),
          ],
        ),
      ),
    );
  }
}

/// Blocking screen for accounts created before a DOB was required.
class DobRequiredScreen extends ConsumerStatefulWidget {
  const DobRequiredScreen({super.key});

  @override
  ConsumerState<DobRequiredScreen> createState() => _DobRequiredScreenState();
}

class _DobRequiredScreenState extends ConsumerState<DobRequiredScreen> {
  DateTime? _dob;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).setDob(_dob!);
      ref.invalidate(myProfileProvider);
      ref.invalidate(hasDobProvider);
    } on AppException catch (e) {
      if (mounted) showSnack(context, e.message, icon: PhosphorIconsFill.warningCircle);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fc;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(PhosphorIconsRegular.cake, size: 44, color: c.ink),
              const SizedBox(height: 18),
              Text('Add your date of birth', style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Vouby is for adults only. Other people see your age, never your date of birth. '
                'You can’t change it later, so please check it carefully.',
                style: t.bodyMedium?.copyWith(color: c.muted),
              ),
              const SizedBox(height: 22),
              DobField(value: _dob, onChanged: (d) => setState(() => _dob = d)),
              const Spacer(),
              PillButton(label: 'Save', busy: _busy, onTap: _dob == null ? null : _save),
              TextButton(
                onPressed: () => ref.read(backendProvider).signOut(),
                child: Text('Sign out', style: t.labelMedium?.copyWith(color: c.ink2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
