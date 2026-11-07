import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile.dart';
import '../../providers.dart';

final _safetyProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, peerId) => ref.watch(backendProvider).safetyNumber(peerId),
);

/// Compare these digits in person (or on a call) to confirm no one is
/// intercepting your encrypted chat. They change if either of you adds or
/// removes a device.
class SafetyNumberScreen extends ConsumerWidget {
  const SafetyNumberScreen({super.key, required this.peer});
  final PublicProfile peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref.watch(_safetyProvider(peer.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Verify encryption')),
      body: number.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (n) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.lock_rounded, size: 48),
            const SizedBox(height: 12),
            Text('Messages and voice notes with ${peer.firstName} are end-to-end encrypted. '
                'Only your devices and theirs hold the keys.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (n == null)
              const Text('Not available in demo mode.', textAlign: TextAlign.center)
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < n.length; i += 5)
                      Text(n.substring(i, i + 5),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text('Compare this number with the one on ${peer.firstName}’s phone. If they match, your chat is secure. '
                'If they don’t, someone may be interfering: stop sharing sensitive information and report it.',
                style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}
