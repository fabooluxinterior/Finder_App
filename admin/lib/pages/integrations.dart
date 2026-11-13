import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../ui.dart';

/// Settings → Integrations & credentials.
/// Shows only "Configured / Not configured", which variables are missing, and
/// the result of a safe live check. Secret values are never sent to the
/// browser. Secrets are added server-side (Supabase dashboard → Edge
/// Functions → Secrets, or `supabase secrets set`), alongside existing ones.
class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key, required this.api});
  final AdminApi api;

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  late Future<List<IntegrationStatus>> _data = widget.api.integrations();
  String? _validating;

  Future<void> _validate(String service) async {
    setState(() => _validating = service);
    try {
      final r = widget.api.integrations(validate: service);
      setState(() {
        _data = r;
      });
      await r;
    } on AdminException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _validating = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<IntegrationStatus>>(
    future: _data,
    builder: (context, s) {
      final items = s.data ?? const <IntegrationStatus>[];
      final missingRequired = items.where((i) => i.required && !i.configured).toList();
      return PageFrame(
        title: 'Integrations & credentials',
        subtitle: 'Status only. Values are never shown; add or rotate them on the server.',
        actions: [
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _data = widget.api.integrations();
            }),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
        children: [
          if (s.hasError)
            SectionCard(
              title: 'Couldn’t load',
              child: Text('${s.error}', style: const TextStyle(color: muted)),
            )
          else if (!s.hasData)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (missingRequired.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Setup needed: ${missingRequired.map((i) => i.label).join(', ')}. '
                    'The app can’t work fully until these are configured.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            for (final i in items) _ServiceCard(i, validating: _validating == i.service, onValidate: () => _validate(i.service)),
            const SectionCard(
              title: 'Adding or changing a credential',
              child: Text(
                '1. Add the new value with `supabase secrets set NAME=value` (or Supabase dashboard → Edge Functions → Secrets).\n'
                '2. Never overwrite or delete an existing key unless the owner approved it (encryption keys: add a new version instead).\n'
                '3. Come back here and press Validate.\n'
                'Secrets never go in the app, the admin web build, the database or Git.',
                style: TextStyle(height: 1.5),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard(this.i, {required this.validating, required this.onValidate});
  final IntegrationStatus i;
  final bool validating;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final (status, color, icon) = !i.configured
        ? ('Not configured', i.required ? accent : warnAmber, Icons.error_outline)
        : i.valid == false
        ? ('Check failed', accent, Icons.error_outline)
        : i.valid == true
        ? ('Configured · working', okGreen, Icons.check_circle_outline)
        : ('Configured', okGreen, Icons.check_circle_outline);
    return SectionCard(
      title: i.label,
      subtitle: i.required ? 'Required' : 'Optional feature',
      trailing: StatusChip(status, color: color, icon: icon),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (i.missing.isNotEmpty) ...[
            Text('Missing: ${i.missing.join(', ')}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              i.setup,
              style: const TextStyle(color: muted, fontFamily: 'monospace', fontSize: 12.5),
            ),
            const SizedBox(height: 10),
          ],
          if (i.message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('${i.message}  (checked ${fmtDate(i.validatedAt)})', style: const TextStyle(color: muted)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: validating ? null : onValidate,
              icon: validating
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Validate'),
            ),
          ),
        ],
      ),
    );
  }
}
