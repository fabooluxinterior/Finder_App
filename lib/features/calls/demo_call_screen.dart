import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/widgets.dart';
import '../../models/profile.dart';
import '../../providers.dart';

/// Demo call: ringing, then connected with a timer. No audio yet (a real calling service plugs in later); the other
/// phone is rung with a notification when the call starts.
class DemoCallScreen extends ConsumerStatefulWidget {
  const DemoCallScreen({super.key, required this.peer});
  final PublicProfile peer;

  @override
  ConsumerState<DemoCallScreen> createState() => _DemoCallScreenState();
}

class _DemoCallScreenState extends ConsumerState<DemoCallScreen> {
  Timer? _tick;
  var _state = 'Calling…';
  var _connected = false;
  var _muted = false;
  var _speaker = false;
  var _secs = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await ref.read(backendProvider).startDemoCall(widget.peer.id);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t start the call. Try again.');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() {
      _state = 'Ringing…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    setState(() {
      _connected = true;
      _state = 'Connected';
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _secs++));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _clock => '${(_secs ~/ 60).toString().padLeft(2, '0')}:${(_secs % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0E0E10);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(99)),
              child: const Text('Demo call · no audio yet', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ),
            const Spacer(),
            Avatar(url: widget.peer.primaryPhoto, name: widget.peer.fullName, size: 132),
            const SizedBox(height: 22),
            Text(
              widget.peer.firstName,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _error ?? (_connected ? _clock : _state),
                key: ValueKey(_error ?? (_connected ? 'clock' : _state)),
                style: TextStyle(color: _error == null ? Colors.white70 : const Color(0xFFFF8A80), fontSize: 16),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Round(
                  icon: _muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                  label: 'Mute',
                  on: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                _Round(
                  icon: _speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                  label: 'Speaker',
                  on: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Semantics(
              button: true,
              label: 'End call',
              child: Material(
                color: const Color(0xFFE5484D),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 72,
                    height: 72,
                    child: Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: on ? Colors.white : Colors.white12,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 62, height: 62, child: Icon(icon, color: on ? Colors.black : Colors.white, size: 28)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ],
  );
}
