/// Support tickets (public.support_tickets).
enum SupportCategory { account, discovery, chat, subscription, privacy, safety, other }

extension SupportCategoryX on SupportCategory {
  String get wire => name;
  String get label => switch (this) {
    SupportCategory.account => 'Account and profile',
    SupportCategory.discovery => 'Discovery and matching',
    SupportCategory.chat => 'Chat and messaging',
    SupportCategory.subscription => 'Subscription and payments',
    SupportCategory.privacy => 'Privacy and security',
    SupportCategory.safety => 'Safety and reporting',
    SupportCategory.other => 'Something else',
  };
  static SupportCategory fromWire(String w) =>
      SupportCategory.values.firstWhere((c) => c.wire == w, orElse: () => SupportCategory.other);
}

enum TicketStatus { newTicket, inProgress, waitingForUser, resolved, closed }

extension TicketStatusX on TicketStatus {
  String get wire => switch (this) {
    TicketStatus.newTicket => 'new',
    TicketStatus.inProgress => 'in_progress',
    TicketStatus.waitingForUser => 'waiting_for_user',
    TicketStatus.resolved => 'resolved',
    TicketStatus.closed => 'closed',
  };
  String get label => switch (this) {
    TicketStatus.newTicket => 'New',
    TicketStatus.inProgress => 'In progress',
    TicketStatus.waitingForUser => 'Waiting for you',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.closed => 'Closed',
  };
  bool get open => this == TicketStatus.newTicket || this == TicketStatus.inProgress || this == TicketStatus.waitingForUser;
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

  SupportTicket copyWith({TicketStatus? status, DateTime? updatedAt}) => SupportTicket(
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
