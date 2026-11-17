/// A message the person chose to send later. Kept on this phone only (encrypted storage) until it is sent;
/// the other person never sees it before then.
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.peerId,
    required this.sendAt,
    required this.createdAt,
    this.text,
    this.hasImage = false,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  final String id;
  final String peerId;
  final DateTime sendAt;
  final DateTime createdAt;
  final String? text;

  /// A photo waits in encrypted storage under [id].
  final bool hasImage;
  final int width;
  final int height;

  /// Why the last attempt failed, when it is not simply "no connection" (that one retries by itself).
  final String? error;

  bool due(DateTime now) => !sendAt.isAfter(now);

  ScheduledMessage copyWith({DateTime? sendAt, String? error, bool clearError = false}) => ScheduledMessage(
    id: id,
    peerId: peerId,
    sendAt: sendAt ?? this.sendAt,
    createdAt: createdAt,
    text: text,
    hasImage: hasImage,
    width: width,
    height: height,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'peer': peerId,
    'at': sendAt.toUtc().toIso8601String(),
    'made': createdAt.toUtc().toIso8601String(),
    if (text != null) 't': text,
    if (hasImage) 'img': true,
    if (hasImage) 'w': width,
    if (hasImage) 'h': height,
    if (error != null) 'err': error,
  };

  factory ScheduledMessage.fromJson(Map<String, dynamic> j) => ScheduledMessage(
    id: j['id'] as String,
    peerId: j['peer'] as String,
    sendAt: DateTime.parse(j['at'] as String).toLocal(),
    createdAt: DateTime.parse(j['made'] as String).toLocal(),
    text: j['t'] as String?,
    hasImage: j['img'] as bool? ?? false,
    width: (j['w'] as num?)?.toInt() ?? 0,
    height: (j['h'] as num?)?.toInt() ?? 0,
    error: j['err'] as String?,
  );
}
