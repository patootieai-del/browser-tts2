import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

abstract class KeepAwake {
  Future<void> acquire();
  Future<void> release();
}

/// PARTIAL_WAKE_LOCK + Wi-Fi lock held natively while reading.
class ChannelKeepAwake implements KeepAwake {
  static const _ch = MethodChannel('vox/keepalive');
  static const _maxHold = Duration(hours: 6); // safety net

  @override
  Future<void> acquire() async {
    try {
      await _ch.invokeMethod('acquire', {'timeoutMs': _maxHold.inMilliseconds});
    } catch (_) {}
  }

  @override
  Future<void> release() async {
    try {
      await _ch.invokeMethod('release');
    } catch (_) {}
  }
}

class BackgroundSetup {
  /// Android 13+: without it the foreground notification (and its media
  /// controls) is hidden, though playback still works.
  static Future<void> ensureNotificationPermission() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  static Future<bool> isUnrestrictedBattery() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestUnrestrictedBattery() async {
    try {
      return (await Permission.ignoreBatteryOptimizations.request()).isGranted;
    } catch (_) {
      return false;
    }
  }
}