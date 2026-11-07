import 'dart:typed_data';

/// In-memory image registry for demo mode (locally picked photos are
/// referenced as `mem:<id>` instead of storage URLs).
class MemoryImages {
  MemoryImages._();
  static final _store = <String, Uint8List>{};
  static int _next = 0;

  static String put(Uint8List bytes) {
    final key = 'mem:${_next++}';
    _store[key] = bytes;
    return key;
  }

  static Uint8List? get(String key) => _store[key];
  static bool isMemory(String url) => url.startsWith('mem:');
}
