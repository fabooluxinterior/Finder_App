import 'profile.dart';

enum SwipeOutcome { passed, requested, matched }

class FollowRequest {
  const FollowRequest({required this.id, required this.sender, required this.createdAt});

  final String id;
  final PublicProfile sender;
  final DateTime createdAt;
}

class Connection {
  const Connection({required this.profile, required this.connectedAt, this.lastMessage, this.unread = 0});

  final PublicProfile profile;
  final DateTime connectedAt;
  final String? lastMessage;
  final int unread;
}

/// Teaser shown to free users: count only, identities withheld by the server.
class IncomingRequests {
  const IncomingRequests({required this.count, required this.requests});

  final int count;

  /// Empty without Fast-Track (server-side RLS hides pending senders).
  final List<FollowRequest> requests;
}
