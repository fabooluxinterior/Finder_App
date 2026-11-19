enum ScheduledStatus { scheduled, sent, failed, cancelled }

/// A message waiting on the server to be sent at [sendAt]. The text is only known on the phone that scheduled it
/// (the server holds the encrypted copy and never sees the text).
class ScheduledItem {
  const ScheduledItem({
    required this.id,
    required this.peerId,
    required this.clientId,
    required this.sendAt,
    required this.status,
    this.text,
    this.timezone,
    this.error,
    this.messageId,
    this.sentAt,
  });

  final String id;
  final String peerId;
  final String clientId;
  final DateTime sendAt;
  final ScheduledStatus status;
  final String? text;
  final String? timezone;
  final String? error;

  /// Once sent: the chat message it became.
  final String? messageId;
  final DateTime? sentAt;

  bool get editable => status == ScheduledStatus.scheduled && (text ?? '').isNotEmpty;
}
