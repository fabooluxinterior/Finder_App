import 'dart:convert';
import 'dart:typed_data';

/// Reference to an end-to-end encrypted attachment. The key never leaves
/// the encrypted message payload; storage only holds ciphertext.
class VoiceRef {
  const VoiceRef({required this.path, required this.key, required this.nonce, required this.sha256, required this.millis});
  final String path;
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List sha256;
  final int millis;

  Map<String, Object> toJson() => {
    'path': path,
    'key': base64Encode(key),
    'nonce': base64Encode(nonce),
    'sha256': base64Encode(sha256),
    'ms': millis,
  };

  factory VoiceRef.fromJson(Map<String, dynamic> j) => VoiceRef(
    path: j['path'] as String,
    key: base64Decode(j['key'] as String),
    nonce: base64Decode(j['nonce'] as String),
    sha256: base64Decode(j['sha256'] as String),
    millis: (j['ms'] as num).toInt(),
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.isRead,
    required this.createdAt,
    this.voice,
    this.localAudioPath,
  });

  /// Server message id (or a client id until confirmed).
  final String id;
  final String senderId;
  final String receiverId;
  final String? content;
  final VoiceRef? voice;

  /// Demo mode only: playable local recording.
  final String? localAudioPath;
  final bool isRead;
  final DateTime createdAt;

  bool get isVoice => voice != null || localAudioPath != null;

  ChatMessage copyWith({String? id, bool? isRead}) => ChatMessage(
    id: id ?? this.id,
    senderId: senderId,
    receiverId: receiverId,
    content: content,
    voice: voice,
    localAudioPath: localAudioPath,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    's': senderId,
    'r': receiverId,
    'c': content,
    'v': voice?.toJson(),
    'read': isRead,
    'at': createdAt.toUtc().toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    senderId: j['s'] as String,
    receiverId: j['r'] as String,
    content: j['c'] as String?,
    voice: j['v'] == null ? null : VoiceRef.fromJson((j['v'] as Map).cast<String, dynamic>()),
    isRead: j['read'] as bool? ?? false,
    createdAt: DateTime.parse(j['at'] as String).toLocal(),
  );
}

/// What travels inside the E2EE ciphertext. `id` is the sender's client
/// message id, bound into the encrypted payload so a relayed or duplicated
/// envelope can be recognised and ignored.
class SecurePayload {
  const SecurePayload({required this.clientId, required this.sentAt, this.text, this.voice});
  final String clientId;
  final DateTime sentAt;
  final String? text;
  final VoiceRef? voice;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'id': clientId,
        'ts': sentAt.toUtc().toIso8601String(),
        if (text != null) 'text': text,
        if (voice != null) 'voice': voice!.toJson(),
      }),
    ),
  );

  factory SecurePayload.decode(Uint8List bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('Unsupported payload version');
    return SecurePayload(
      clientId: j['id'] as String,
      sentAt: DateTime.parse(j['ts'] as String),
      text: j['text'] as String?,
      voice: j['voice'] == null ? null : VoiceRef.fromJson((j['voice'] as Map).cast<String, dynamic>()),
    );
  }
}
