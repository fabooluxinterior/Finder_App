class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.audioUrl,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String? content;

  /// Storage path (Supabase) or playable URL (demo).
  final String? audioUrl;
  final bool isRead;
  final DateTime createdAt;

  bool get isVoice => audioUrl != null;

  factory ChatMessage.fromRow(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String,
        receiverId: m['receiver_id'] as String,
        content: m['content'] as String?,
        audioUrl: m['audio_url'] as String?,
        isRead: (m['is_read'] as bool?) ?? false,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
