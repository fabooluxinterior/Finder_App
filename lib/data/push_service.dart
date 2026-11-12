// ignore_for_file: deprecated_member_use
// The classic registration-token API is what the HTTP v1 sender targets (token: ...); the newer
// FID-based API is a different send mode. Revisit when the server side moves to it.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/config.dart';

/// Phone popup notifications (Firebase Cloud Messaging). Only public identifiers
/// are in the build; the secret key that sends messages lives on the server.
abstract class PushService {
  /// False when the build has no Firebase values or the platform can't do push.
  bool get available;

  /// Asks the user for permission (Android 13+) and returns this phone's token,
  /// or null when permission is refused or push is unavailable.
  Future<String?> requestToken();

  /// This phone's token without asking for permission, or null.
  Future<String?> currentToken();

  Stream<String> get tokenRefreshes;

  /// Messages that arrive while the app is open (the system shows no popup then).
  Stream<PushNotice> get foregroundMessages;

  Future<void> deleteToken();
}

class PushNotice {
  const PushNotice(this.title, this.body, {this.kind = ''});
  final String title;
  final String body;

  /// 'message' for chat messages (the open app already shows those live), 'announcement' for dashboard sends.
  final String kind;
}

class NoopPush implements PushService {
  const NoopPush();
  @override
  bool get available => false;
  @override
  Future<String?> requestToken() async => null;
  @override
  Future<String?> currentToken() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<PushNotice> get foregroundMessages => const Stream.empty();
  @override
  Future<void> deleteToken() async {}
}

class FirebasePush implements PushService {
  FirebasePush._();

  /// Null when the build has no Firebase configuration (push stays off).
  static Future<PushService> create() async {
    if (!AppConfig.pushConfigured) return const NoopPush();
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      return FirebasePush._();
    } catch (_) {
      return const NoopPush();
    }
  }

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  bool get available => true;

  @override
  Future<String?> requestToken() async {
    try {
      final settings = await _fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      return await _fm.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> currentToken() async {
    try {
      return await _fm.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes => _fm.onTokenRefresh;

  @override
  Stream<PushNotice> get foregroundMessages => FirebaseMessaging.onMessage
      .where((m) => m.notification != null)
      .map((m) => PushNotice(m.notification!.title ?? '', m.notification!.body ?? '', kind: m.data['kind'] as String? ?? ''));

  @override
  Future<void> deleteToken() async {
    try {
      await _fm.deleteToken();
    } catch (_) {}
  }
}
