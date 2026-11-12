import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification-bar alerts raised by the app itself when a message arrives
/// while the app is open in the background (it keeps its live connection for a
/// while). No Firebase needed. When the app is fully closed, Firebase push
/// (push_service.dart) takes over once it is configured.
abstract class LocalNotifier {
  bool get available;

  /// Asks Android for permission to show notifications. True when allowed.
  Future<bool> requestPermission();

  /// Shows (or replaces) one notification per chat. The text of a message is
  /// never put on the lock screen.
  Future<void> showMessage({required String peerId, required String name});
}

class NoopLocalNotifier implements LocalNotifier {
  const NoopLocalNotifier();
  @override
  bool get available => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> showMessage({required String peerId, required String name}) async {}
}

class AndroidLocalNotifier implements LocalNotifier {
  AndroidLocalNotifier._(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  @override
  bool get available => true;

  static Future<LocalNotifier> create() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const NoopLocalNotifier();
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')));
      // High importance = the banner slides down from the top of the screen like WhatsApp or PhonePe.
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      for (final ch in const [('messages', 'Messages'), ('announcements', 'Announcements')]) {
        await android?.createNotificationChannel(
          AndroidNotificationChannel(ch.$1, ch.$2, importance: Importance.high, playSound: true, enableVibration: true),
        );
      }
      return AndroidLocalNotifier._(plugin);
    } catch (_) {
      return const NoopLocalNotifier();
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showMessage({required String peerId, required String name}) async {
    try {
      await _plugin.show(
        id: peerId.hashCode & 0x7fffffff,
        title: name,
        body: 'Sent you a message',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'New chat messages',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_notification',
            color: Color(0xFFFF5A3D),
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.private,
          ),
        ),
      );
    } catch (_) {}
  }
}
