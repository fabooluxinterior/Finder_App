import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('vouby/app');

/// Android back on a root screen: keep the app running in the background
/// (like pressing Home) instead of closing it. Elsewhere it's a no-op.
Future<void> sendAppToBackground() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<bool>('moveToBackground');
  } on PlatformException {
    await SystemNavigator.pop();
  } on MissingPluginException {
    await SystemNavigator.pop();
  }
}
