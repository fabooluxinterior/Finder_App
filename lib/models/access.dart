/// What the server says about the user's access (public.my_access_status).
/// The app only reflects this; every gate is enforced on the server.
class AccessStatus {
  const AccessStatus({this.plan = AccessPlan.free, this.trialStartedAt, this.trialEndsAt, this.trialUsed = false, this.notice});

  final AccessPlan plan;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final bool trialUsed;

  /// 'trial_24h' or 'trial_ended' when a reminder should be shown.
  final String? notice;

  bool get hasChatAccess => plan != AccessPlan.free;
  bool get inTrial => plan == AccessPlan.trial;

  /// Whole days left, rounded up ("5 days left"); 0 when ended.
  int daysLeft(DateTime now) {
    final end = trialEndsAt;
    if (end == null || !end.isAfter(now)) return 0;
    return (end.difference(now).inMinutes / (24 * 60)).ceil();
  }

  Duration timeLeft(DateTime now) {
    final end = trialEndsAt;
    if (end == null || !end.isAfter(now)) return Duration.zero;
    return end.difference(now);
  }

  factory AccessStatus.fromJson(Map<String, dynamic> m) => AccessStatus(
    plan: switch (m['plan']) {
      'fast_track' => AccessPlan.fastTrack,
      'trial' => AccessPlan.trial,
      _ => AccessPlan.free,
    },
    trialStartedAt: DateTime.tryParse(m['trial_started_at'] as String? ?? '')?.toLocal(),
    trialEndsAt: DateTime.tryParse(m['trial_ends_at'] as String? ?? '')?.toLocal(),
    trialUsed: (m['trial_used'] as bool?) ?? false,
    notice: m['notice'] as String?,
  );
}

enum AccessPlan { free, trial, fastTrack }

/// Exactly 7 days.
const trialLength = Duration(hours: 168);

/// Fast-Track price shown everywhere it's sold (Play Billing charges it).
const fastTrackMonthlyRupees = 79;

/// ₹79 ÷ 30 days, rounded to paise: "₹2.63".
String perDayPrice({int monthly = fastTrackMonthlyRupees, int days = 30}) => '₹${(monthly / days).toStringAsFixed(2)}';

/// An in-app notice (trial reminders, ticket updates, moderation notices).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });
  final int id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  factory AppNotification.fromJson(Map<String, dynamic> m) => AppNotification(
    id: (m['id'] as num).toInt(),
    kind: m['kind'] as String,
    title: m['title'] as String,
    body: m['body'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    readAt: DateTime.tryParse(m['read_at'] as String? ?? '')?.toLocal(),
  );
}

/// The user's own current restriction (warning / restricted / suspended / banned).
class AccountRestriction {
  const AccountRestriction({required this.kind, required this.reason, this.until});
  final String kind;
  final String reason;
  final DateTime? until;
}
