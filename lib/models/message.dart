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

/// Reference to an end-to-end encrypted photo (same scheme as voice notes:
/// storage only holds ciphertext; the key travels inside the E2EE payload).
class ImageRef {
  const ImageRef({
    required this.path,
    required this.key,
    required this.nonce,
    required this.sha256,
    required this.width,
    required this.height,
  });
  final String path;
  final Uint8List key;
  final Uint8List nonce;
  final Uint8List sha256;
  final int width;
  final int height;

  Map<String, Object> toJson() => {
    'path': path,
    'key': base64Encode(key),
    'nonce': base64Encode(nonce),
    'sha256': base64Encode(sha256),
    'w': width,
    'h': height,
  };

  factory ImageRef.fromJson(Map<String, dynamic> j) => ImageRef(
    path: j['path'] as String,
    key: base64Decode(j['key'] as String),
    nonce: base64Decode(j['nonce'] as String),
    sha256: base64Decode(j['sha256'] as String),
    width: (j['w'] as num?)?.toInt() ?? 0,
    height: (j['h'] as num?)?.toInt() ?? 0,
  );
}

/// Shown by app versions from before photo messages.
const photoFallbackText = '📷 Photo — update Vouby to view it';

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
    this.image,
    this.localImageUrl,
    this.edited = false,
    this.deleted = false,
  });

  /// Server message id (or a client id until confirmed).
  final String id;
  final String senderId;
  final String receiverId;
  final String? content;
  final VoiceRef? voice;

  /// Demo mode only: playable local recording.
  final String? localAudioPath;
  final ImageRef? image;

  /// Demo mode only: an in-memory image URL.
  final String? localImageUrl;
  bool get isImage => image != null || localImageUrl != null;
  final bool isRead;
  final DateTime createdAt;

  /// The sender changed the text after sending.
  final bool edited;

  /// The sender deleted it for everyone: nothing of the original is kept.
  final bool deleted;

  bool get isVoice => voice != null || localAudioPath != null;

  ChatMessage copyWith({String? id, bool? isRead}) => ChatMessage(
    id: id ?? this.id,
    senderId: senderId,
    receiverId: receiverId,
    content: content,
    voice: voice,
    localAudioPath: localAudioPath,
    image: image,
    localImageUrl: localImageUrl,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    edited: edited,
    deleted: deleted,
  );

  /// The same message with new text, marked "edited".
  ChatMessage withEditedText(String text) => ChatMessage(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    content: text,
    isRead: isRead,
    createdAt: createdAt,
    edited: true,
  );

  /// Deleted for everyone: the content, voice note and photo reference are dropped.
  ChatMessage asDeleted() => ChatMessage(
    id: id,
    senderId: senderId,
    receiverId: receiverId,
    content: null,
    isRead: isRead,
    createdAt: createdAt,
    deleted: true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    's': senderId,
    'r': receiverId,
    'c': content,
    'v': voice?.toJson(),
    if (image != null) 'img': image!.toJson(),
    'read': isRead,
    'at': createdAt.toUtc().toIso8601String(),
    if (edited) 'ed': true,
    if (deleted) 'del': true,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    senderId: j['s'] as String,
    receiverId: j['r'] as String,
    content: j['c'] as String?,
    voice: j['v'] == null ? null : VoiceRef.fromJson((j['v'] as Map).cast<String, dynamic>()),
    image: j['img'] == null ? null : ImageRef.fromJson((j['img'] as Map).cast<String, dynamic>()),
    isRead: j['read'] as bool? ?? false,
    createdAt: DateTime.parse(j['at'] as String).toLocal(),
    edited: j['ed'] as bool? ?? false,
    deleted: j['del'] as bool? ?? false,
  );
}

/// What travels inside the E2EE ciphertext. `id` is the sender's client
/// message id, bound into the encrypted payload so a relayed or duplicated
/// envelope can be recognised and ignored.
class SecurePayload {
  const SecurePayload({
    required this.clientId,
    required this.sentAt,
    this.text,
    this.voice,
    this.image,
    this.editTarget,
    this.deleteTarget,
  });
  final String clientId;
  final DateTime sentAt;
  final String? text;
  final VoiceRef? voice;
  final ImageRef? image;

  /// Control payloads: change or delete an earlier message (its server id). Only honoured when they
  /// come from that message's own sender. [text] carries the new text for an edit.
  final String? editTarget;
  final String? deleteTarget;
  bool get isControl => editTarget != null || deleteTarget != null;

  /// What an older app version shows for a control message (it has no idea what to do with it).
  static const deleteFallbackText = 'This message was deleted.';

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'id': clientId,
        'ts': sentAt.toUtc().toIso8601String(),
        // Older app versions only understand text/voice: give them a hint.
        if (deleteTarget != null)
          'text': deleteFallbackText
        else if (editTarget != null)
          'text': 'Edited: $text'
        else if (text != null)
          'text': text
        else if (image != null)
          'text': photoFallbackText,
        if (voice != null) 'voice': voice!.toJson(),
        if (image != null) 'image': image!.toJson(),
        if (editTarget != null) 'edit': {'t': editTarget, 'text': text},
        if (deleteTarget != null) 'del': deleteTarget,
      }),
    ),
  );

  factory SecurePayload.decode(Uint8List bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['v'] != 1) throw const FormatException('Unsupported payload version');
    final edit = j['edit'] as Map?;
    return SecurePayload(
      clientId: j['id'] as String,
      sentAt: DateTime.parse(j['ts'] as String),
      editTarget: edit?['t'] as String?,
      deleteTarget: j['del'] as String?,
      text: edit != null
          ? edit['text'] as String?
          : j['del'] != null
          ? null
          : j['image'] != null && j['text'] == photoFallbackText
          ? null
          : j['text'] as String?,
      voice: j['voice'] == null ? null : VoiceRef.fromJson((j['voice'] as Map).cast<String, dynamic>()),
      image: j['image'] == null ? null : ImageRef.fromJson((j['image'] as Map).cast<String, dynamic>()),
    );
  }
}
