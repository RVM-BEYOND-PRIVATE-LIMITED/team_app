import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Every error in the app funnels through here.
///
/// What lands in the Firebase console for each report:
/// - device model + name, OS name + version (explicit custom keys below AND
///   the console's own device section),
/// - the real reason (exception message, backend error text, or stack),
/// - the date and time (the console stamps every event).
///
/// Without a Firebase project yet (`google-services.json` not added) the app
/// keeps working: reports fall back to the debug log and the on-screen toast.
abstract final class CrashReporter {
  static bool _available = false;

  /// True once Firebase initialised successfully.
  static bool get available => _available;

  /// Opt-in at build time: `--dart-define=USE_FIREBASE=true`.
  /// Default is OFF so a build without `google-services.json` never even
  /// touches the Firebase native plugin (no throw, no IDE pause).
  /// Flip it on once the Firebase console config file is in place.
  static const _useFirebase =
      bool.fromEnvironment('USE_FIREBASE', defaultValue: false);

  static Future<void> init() async {
    if (!_useFirebase) {
      debugPrint('Crashlytics disabled (build without USE_FIREBASE).');
      return;
    }
    try {
      await Firebase.initializeApp();
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(true);
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
        await FirebaseCrashlytics.instance
            .setCustomKey(entry.key, entry.value);
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
