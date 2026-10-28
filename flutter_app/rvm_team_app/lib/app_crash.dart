import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'firebase_bootstrap.dart';

/// Every error in the app funnels through here.
///
/// What lands in the Firebase console for each report:
/// - device model + name, OS name + version (explicit custom keys below AND
///   the console's own device section),
/// - the real reason (exception message, backend error text, or stack),
/// - the date and time (the console stamps every event).
///
/// The Firebase project `rvm-team-app-2026` is configured for Android through
/// `android/app/google-services.json` and `lib/firebase_options.dart`. A build
/// without that config still runs: reports fall back to the debug log and the
/// on-screen toast.
abstract final class CrashReporter {
  static bool _available = false;

  /// True once Firebase initialised successfully.
  static bool get available => _available;

  /// Build-time switch. Firebase is ON by default now that the project's
  /// `google-services.json` and `firebase_options.dart` are in the repo.
  /// A build without that config catches the init failure and stays local-only;
  /// pass `--dart-define=USE_FIREBASE=false` to switch it off deliberately.
  static const _useFirebase =
      bool.fromEnvironment('USE_FIREBASE', defaultValue: true);

  static Future<void> init() async {
    if (!_useFirebase) {
      debugPrint('Crashlytics disabled (build without USE_FIREBASE).');
      return;
    }
    try {
      await ensureFirebase();
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
      _available = true;
      await _setContextKeys();
      await FirebaseCrashlytics.instance.log('Team RVM started');
    } catch (_) {
      // No google-services.json / no Firebase project yet: stay local-only.
      _available = false;
    }
  }

  static Future<void> _setContextKeys() async {
    try {
      final fields = await _deviceFields();
      for (final entry in fields.entries) {
        await FirebaseCrashlytics.instance.setCustomKey(entry.key, entry.value);
      }
      final pkg = await PackageInfo.fromPlatform();
      await FirebaseCrashlytics.instance
          .setCustomKey('app_version', pkg.version);
      await FirebaseCrashlytics.instance
          .setCustomKey('app_build', pkg.buildNumber);
      await FirebaseCrashlytics.instance
          .setCustomKey('app_package', pkg.packageName);
    } catch (_) {
      // Context keys are nice-to-have; never block startup on them.
    }
  }

  static Future<Map<String, String>> _deviceFields() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        return {
          'device_model': info.model,
          'device_name': '${info.manufacturer} ${info.device}'.trim(),
          'device_brand': info.brand,
          'os_name': 'Android',
          'os_version': '${info.version.release} (SDK ${info.version.sdkInt})',
        };
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        return {
          'device_model': info.model,
          'device_name': info.name,
          'device_brand': 'Apple',
          'os_name': info.systemName,
          'os_version': info.systemVersion,
        };
      }
      final base = await plugin.deviceInfo;
      final data = base.data;
      return {
        'device_model': '${data['model'] ?? ''}',
        'device_name': '${data['name'] ?? data['host'] ?? ''}',
        'device_brand': '${data['brand'] ?? data['manufacturer'] ?? ''}',
        'os_name': defaultTargetPlatform.name,
        'os_version': '${data['version'] ?? ''}',
      };
    } catch (_) {
      return const {};
    }
  }

  /// Remembers context shown next to the crash (e.g. the message the user
  /// saw as a toast). Never throws.
  static void note(String key, String value) {
    if (!_available) return;
    try {
      FirebaseCrashlytics.instance.setCustomKey(key, value);
    } catch (_) {
      // Reporting must never crash the app it is watching.
    }
  }

  /// Records a framework error (`FlutterError.onError` call sites).
  /// Presents the error when Crashlytics is unavailable; otherwise
  /// `recordFlutterError` presents it itself.
  static Future<void> flutterError(FlutterErrorDetails details) async {
    if (!_available) {
      FlutterError.presentError(details);
      return;
    }
    try {
      await FirebaseCrashlytics.instance.recordFlutterError(details);
    } catch (_) {
      FlutterError.presentError(details);
    }
  }

  /// Records anything else that escaped (zone, platform, bloc, data layer).
  /// `fatal: true` is for errors after which the app cannot safely continue
  /// (zone/platform); the app keeps running — the report is uploaded on the
  /// next launch if the process dies before the flush completes.
  static Future<void> record(Object error, StackTrace? stack,
      {String? reason, bool fatal = false}) async {
    final summary = reason ?? error.toString();
    debugPrint('RVM error${fatal ? ' (fatal)' : ''}: $summary');
    if (stack != null) debugPrint('$stack');
    if (!_available) return;
    try {
      await FirebaseCrashlytics.instance.setCustomKey('reason', _clip(summary));
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
        printDetails: false,
      );
    } catch (_) {
      // Reporting must never crash the app it is watching.
    }
  }

  /// A deliberate fatal test report for the Home screen's "Send test crash"
  /// It never kills the process: Crashlytics records it as a fatal event with
  /// the reason `crash-test-button`, so it is easy to find in the console.
  /// Returns false when Firebase is not available in this build.
  static Future<bool> testCrash() async {
    const reason = 'crash-test-button';
    const message = 'Team RVM test crash from the Home screen';
    final stack = StackTrace.current;
    debugPrint('RVM test crash requested: $message');
    debugPrint('$stack');
    if (!_available) {
      debugPrint(
          'Crashlytics is not enabled in this build. Build with Firebase config or --dart-define=USE_FIREBASE=true.');
      return false;
    }
    try {
      await FirebaseCrashlytics.instance.log('Team RVM test crash requested');
      await FirebaseCrashlytics.instance.setCustomKey('reason', reason);
      await FirebaseCrashlytics.instance.setCustomKey('crash_test', 'true');
      await FirebaseCrashlytics.instance.recordError(
        StateError(message),
        stack,
        reason: reason,
        fatal: true,
        printDetails: false,
      );
      return true;
    } catch (error, stack) {
      debugPrint('RVM test crash could not be sent: $error\n$stack');
      return false;
    }
  }

  static String _clip(String value) =>
      value.length <= 1000 ? value : '${value.substring(0, 1000)}…';

  /// `METHOD /path` with id-like segments redacted — safe for the dashboard,
  /// no tokens (tokens travel in headers, never in paths here).
  static String apiLine(String method, String path) {
    final redacted = path.split('/').map((s) {
      if (s.isEmpty) return s;
      final isId = RegExp(r'^[0-9a-fA-F-]{20,}$').hasMatch(s) ||
          (RegExp(r'^\d+$').hasMatch(s) && s.length >= 4);
      return isId ? '{id}' : s;
    }).join('/');
    return '$method $redacted';
  }
}
