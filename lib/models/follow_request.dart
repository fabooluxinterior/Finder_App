import 'profile.dart';

enum SwipeOutcome { passed, requested, matched }

class FollowRequest {
  const FollowRequest({required this.id, required this.sender, required this.createdAt, this.introPromptId, this.introText});

  final String id;
  final PublicProfile sender;
  final DateTime createdAt;

  /// Set when the request came from a reply to one of your prompts.
  final String? introPromptId;
  final String? introText;
}

class Connection {
  const Connection({
    required this.profile,
    required this.connectedAt,
    this.lastMessage,
    this.unread = 0,
    this.introPromptId,
    this.introText,
    this.introFromMe = false,
    this.iFollow = false,
    this.followsMe = false,
    this.lastAt,
  });

  final PublicProfile profile;
  final DateTime connectedAt;
  final String? lastMessage;
  final int unread;

  /// When the last message was sent or received (null until you have messaged).
  final DateTime? lastAt;

  /// Direction of the accepted request: you sent it (you follow them) and/or they sent it (they follow you).
  /// Only you ever see these.
  final bool iFollow;
  final bool followsMe;
  bool get isMutual => iFollow && followsMe;

  /// Shown in the Chats list only once somebody has written.
  bool get hasChat => lastMessage != null;

  /// The prompt reply that started this connection, if any. It travelled
  /// with the follow request (before chat unlocked), so it isn't end-to-end
  /// encrypted; the UI says so.
  final String? introPromptId;
  final String? introText;
  final bool introFromMe;
}

/// Teaser shown to free users: count only, identities withheld by the server.
class IncomingRequests {
  const IncomingRequests({required this.count, required this.requests});

  final int count;

  /// Empty without Fast-Track (server-side RLS hides pending senders).
  final List<FollowRequest> requests;
}

/// Someone you blocked (shown only to you, in Blocked users).
class BlockedUser {
  const BlockedUser({required this.id, required this.fullName, required this.city, required this.blockedAt});
  final String id;
  final String fullName;
  final String city;
  final DateTime blockedAt;
  String get firstName => fullName.split(' ').first;
}
