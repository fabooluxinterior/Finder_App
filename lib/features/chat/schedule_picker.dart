import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// "Send later": quick choices or any date and time. Returns the chosen moment (always in the future) or null.
Future<DateTime?> pickSendTime(BuildContext context, {DateTime? initial}) async {
  final c = context.fc;
  final now = DateTime.now();
  DateTime atHour(DateTime day, int h) => DateTime(day.year, day.month, day.day, h);
  final tonight = atHour(now, 21);
  final tomorrow = atHour(now.add(const Duration(days: 1)), 9);
  final fmt = DateFormat('EEE, d MMM · h:mm a');
  final choice = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: c.surface,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send later',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Vouby sends it at that time while the app is open. If your phone is offline then, it is sent as soon as you are back online.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.ink3),
            ),
            const SizedBox(height: 8),
            if (tonight.isAfter(now.add(const Duration(minutes: 1))))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('Tonight'),
                subtitle: Text(fmt.format(tonight)),
                onTap: () => Navigator.pop(ctx, tonight),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Tomorrow morning'),
              subtitle: Text(fmt.format(tomorrow)),
              onTap: () => Navigator.pop(ctx, tomorrow),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Pick date and time'),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice is DateTime) return choice;
  if (choice != 'custom' || !context.mounted) return null;
  final start = initial != null && initial.isAfter(now) ? initial : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start));
  if (time == null) return null;
  final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!at.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a time in the future.')));
    }
    return null;
  }
  return at;
}
