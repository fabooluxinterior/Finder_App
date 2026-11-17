import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'config.dart';

/// Attached to support tickets so the team can reproduce a problem. Nothing personal.
String appVersionLabel() => AppConfig.buildNumber > 0 ? 'build ${AppConfig.buildNumber}' : 'dev build';

String deviceLabel() {
  if (kIsWeb) return 'Web browser';
  final os = defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android';
  var v = '';
  try {
    v = Platform.operatingSystemVersion;
  } catch (_) {}
  final s = '$os $v'.trim();
  return s.length > 110 ? s.substring(0, 110) : s;
}
