import 'dart:async';

/// What the other person in a chat is doing right now.
enum PeerState {
  idle,
  typing,
  recording,
  photo;

  /// The words shown under the last message ("typing…" with animated dots).
  String get words => switch (this) {
    idle => '',
    typing => 'typing',
    recording => 'recording audio',
    photo => 'sending a photo',
  };

  /// Replaces the city under their name in the chat header.
  String get header => switch (this) {
    idle => '',
    typing => 'typing…',
    recording => 'recording audio…',
    photo => 'sending a photo…',
  };

  /// How long a state lasts without being refreshed. Typing and recording are
  /// re-sent every 2.5 s; a photo upload is one signal, so it lasts longer.
  Duration get hold => this == photo ? const Duration(seconds: 30) : const Duration(seconds: 4);

  static PeerState parse(Object? v) => PeerState.values.firstWhere((s) => s.name == v, orElse: () => PeerState.idle);
}

/// How often the sender repeats a state while it lasts.
const presenceRefresh = Duration(milliseconds: 2500);

/// Turns a stream of signals into a stream that also falls back to [PeerState.idle]
/// when a state is not refreshed in time (closed app, lost connection).
Stream<PeerState> withDecay(Stream<PeerState> source) {
  late StreamController<PeerState> out;
  StreamSubscription<PeerState>? sub;
  Timer? timer;
  out = StreamController<PeerState>(
    onListen: () {
      out.add(PeerState.idle);
      sub = source.listen(
        (s) {
          timer?.cancel();
          out.add(s);
          if (s != PeerState.idle) timer = Timer(s.hold, () => out.add(PeerState.idle));
        },
        onError: out.addError,
        onDone: out.close,
      );
    },
    onCancel: () {
      timer?.cancel();
      return sub?.cancel();
    },
  );
  return out.stream;
}
