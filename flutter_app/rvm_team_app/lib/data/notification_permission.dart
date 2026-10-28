import 'package:permission_handler/permission_handler.dart';

/// Asks for the Android 13+ POST_NOTIFICATIONS grant so the Inbox can show
/// alerts. Best-effort: a refusal (or an OS without the permission) leaves the
/// app fully usable, so every failure is swallowed here.
class NotificationPermission {
  const NotificationPermission();

  Future<void> requestIfNeeded() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Nothing to show: the Inbox still loads, it just cannot raise alerts.
    }
  }
}
