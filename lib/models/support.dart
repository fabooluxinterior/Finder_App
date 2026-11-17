/// Support tickets (public.support_tickets).
enum SupportCategory { account, profile, discovery, chat, subscription, privacy, safety, technical, other }

extension SupportCategoryX on SupportCategory {
  String get wire => name;
  String get label => switch (this) {
    SupportCategory.account => 'Account & Login',
    SupportCategory.profile => 'Profile & Verification',
    SupportCategory.discovery => 'Matches & Likes',
    SupportCategory.chat => 'Chat & Messages',
    SupportCategory.subscription => 'Payments & Subscription',
    SupportCategory.privacy => 'Privacy & Security',
    SupportCategory.safety => 'Safety & Reporting',
    SupportCategory.technical => 'Technical Issues',
    SupportCategory.other => 'Something else',
  };
  static SupportCategory fromWire(String w) =>
      SupportCategory.values.firstWhere((c) => c.wire == w, orElse: () => SupportCategory.other);

  /// The seven topics shown on the Help home (everything except privacy and "something else", which tickets still allow).
  static const helpTopics = [
    SupportCategory.account,
    SupportCategory.profile,
    SupportCategory.discovery,
    SupportCategory.chat,
    SupportCategory.subscription,
    SupportCategory.safety,
    SupportCategory.technical,
  ];
}

enum TicketPriority { low, normal, high, urgent }

extension TicketPriorityX on TicketPriority {
  String get wire => name;
  String get label => switch (this) {
    TicketPriority.low => 'Low',
    TicketPriority.normal => 'Normal',
    TicketPriority.high => 'High',
    TicketPriority.urgent => 'Urgent',
  };
  static TicketPriority fromWire(String? w) =>
      TicketPriority.values.firstWhere((p) => p.wire == w, orElse: () => TicketPriority.normal);
}

enum TicketStatus { newTicket, open, assigned, inProgress, waitingForUser, escalated, resolved, closed }

extension TicketStatusX on TicketStatus {
  String get wire => switch (this) {
    TicketStatus.newTicket => 'new',
    TicketStatus.open => 'open',
    TicketStatus.assigned => 'assigned',
    TicketStatus.inProgress => 'in_progress',
    TicketStatus.waitingForUser => 'waiting_for_user',
    TicketStatus.escalated => 'escalated',
    TicketStatus.resolved => 'resolved',
    TicketStatus.closed => 'closed',
  };
  String get label => switch (this) {
    TicketStatus.newTicket => 'Open',
    TicketStatus.open => 'Open',
    TicketStatus.assigned => 'Assigned',
    TicketStatus.inProgress => 'In progress',
    TicketStatus.waitingForUser => 'Waiting for you',
    TicketStatus.escalated => 'Escalated',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.closed => 'Closed',
  };
  bool get open => this != TicketStatus.resolved && this != TicketStatus.closed;
  static TicketStatus fromWire(String w) =>
      TicketStatus.values.firstWhere((s) => s.wire == w, orElse: () => TicketStatus.newTicket);
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketNo,
    required this.category,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.hasAttachment = false,
    this.userId,
    this.priority = TicketPriority.normal,
    this.rating,
    this.botConversationId,
  });
  final String id;
  final String ticketNo;
  final SupportCategory category;
  final String subject;
  final String description;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? email;
  final bool hasAttachment;
  final String? userId;
  final TicketPriority priority;
  final int? rating;
  final String? botConversationId;

  /// A resolved ticket can be reopened; a closed one for 14 days after it was closed.
  bool get canReopen =>
      status == TicketStatus.resolved ||
      (status == TicketStatus.closed && DateTime.now().difference(updatedAt) < const Duration(days: 14));
  bool get canRate => (status == TicketStatus.resolved || status == TicketStatus.closed) && rating == null;

  SupportTicket copyWith({TicketStatus? status, DateTime? updatedAt, int? rating}) => SupportTicket(
    id: id,
    ticketNo: ticketNo,
    category: category,
    subject: subject,
    description: description,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    email: email,
    hasAttachment: hasAttachment,
    userId: userId,
    priority: priority,
    rating: rating ?? this.rating,
    botConversationId: botConversationId,
  );

  factory SupportTicket.fromJson(Map<String, dynamic> m) => SupportTicket(
    id: m['id'] as String,
    ticketNo: m['ticket_no'] as String,
    category: SupportCategoryX.fromWire(m['category'] as String),
    subject: m['subject'] as String,
    description: m['description'] as String,
    status: TicketStatusX.fromWire(m['status'] as String),
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
    email: m['email'] as String?,
    hasAttachment: m['attachment_path'] != null,
    userId: m['user_id'] as String?,
    priority: TicketPriorityX.fromWire(m['priority'] as String?),
    rating: (m['rating'] as num?)?.toInt(),
    botConversationId: m['bot_conversation_id'] as String?,
  );
}

/// One message in a ticket's conversation: the person's or the team's.
class TicketMessage {
  const TicketMessage({required this.id, required this.fromStaff, required this.body, required this.createdAt});
  final int id;
  final bool fromStaff;
  final String body;
  final DateTime createdAt;

  factory TicketMessage.fromJson(Map<String, dynamic> m) => TicketMessage(
    id: (m['id'] as num).toInt(),
    fromStaff: (m['from_staff'] as bool?) ?? false,
    body: m['body'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );
}

/// Client-side validation (the server checks the same limits).
String? validateTicket({required String subject, required String description}) {
  if (subject.trim().length < 3) return 'Add a short subject (at least 3 characters).';
  if (subject.trim().length > 120) return 'Keep the subject under 120 characters.';
  if (description.trim().length < 10) return 'Describe the issue in a few words (at least 10 characters).';
  if (description.trim().length > 4000) return 'Keep the description under 4000 characters.';
  return null;
}

/// One step of a ticket's history ("Assigned", "Resolved"...).
class TicketEvent {
  const TicketEvent({required this.status, required this.at, this.note});
  final TicketStatus status;
  final DateTime at;
  final String? note;
}

/// What the support chatbot says and offers, edited by admins in the dashboard.
class BotConfig {
  const BotConfig({
    required this.enabled,
    required this.welcome,
    required this.fallback,
    required this.resolvedPrompt,
    required this.ticketPrompt,
    required this.quickReplies,
  });
  final bool enabled;
  final String welcome;
  final String fallback;
  final String resolvedPrompt;
  final String ticketPrompt;
  final List<String> quickReplies;

  factory BotConfig.fromJson(Map<String, dynamic> j) => BotConfig(
    enabled: (j['enabled'] as bool?) ?? true,
    welcome: (j['welcome'] as String?) ?? 'Hi! Welcome to Vouby Support. How can we help you today?',
    fallback: (j['fallback'] as String?) ?? 'Sorry, I didn’t quite get that. Could you rephrase it, or raise a support ticket?',
    resolvedPrompt: (j['resolved_prompt'] as String?) ?? 'Did that solve your issue?',
    ticketPrompt: (j['ticket_prompt'] as String?) ?? 'You can raise a support ticket and our team will help.',
    quickReplies: [for (final q in (j['quick_replies'] as List? ?? const [])) '$q'],
  );
}

class FaqEntry {
  const FaqEntry({required this.id, required this.category, required this.title, required this.answer});
  final String id;
  final SupportCategory category;
  final String title;
  final String answer;

  factory FaqEntry.fromJson(Map<String, dynamic> j) => FaqEntry(
    id: j['id'] as String,
    category: SupportCategoryX.fromWire(j['category'] as String),
    title: j['title'] as String,
    answer: j['answer'] as String,
  );
}

/// The chatbot's best answer to what was typed, and a few related questions.
class BotAnswer {
  const BotAnswer({required this.entry, this.related = const []});
  final FaqEntry entry;
  final List<({String id, String title})> related;
}

/// A saved chatbot conversation. Each message: {mine, text, kind?, id?}.
class BotConversation {
  const BotConversation({required this.id, required this.messages});
  final String id;
  final List<Map<String, dynamic>> messages;
}
