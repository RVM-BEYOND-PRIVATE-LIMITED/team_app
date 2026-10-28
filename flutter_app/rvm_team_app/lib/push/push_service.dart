import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../app_feedback.dart';
import '../bloc/team_auth_bloc.dart';
import '../firebase_bootstrap.dart';
import '../injection.dart';

/// The channel Firebase notifications fall back to when a message does not
/// name one. Declared as `default_notification_channel_id` in the manifest too.
const notificationChannelId = 'team_rvm_alerts';
const _channelName = 'Team RVM alerts';
const _channelDescription = 'Tasks, approvals, announcements and reminders';

/// Runs in a separate isolate when a push arrives while the app is in the
/// background or terminated. Notification payloads are drawn by FCM itself;
/// data-only payloads (no `notification` block) are drawn here so they are
/// never silently lost.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await ensureFirebase();
    if (message.notification != null) return;
    if (!_isAndroid) return;

    final title = _text(message.data['title'] ?? message.data['subject']);
    final body = _text(message.data['body'] ?? message.data['message']);
    if (title.isEmpty && body.isEmpty) return;

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    final imagePath = await _downloadImage(_imageUrlOf(message));
    await _showNotification(
      plugin,
      id: _idFor(message),
      title: title.isEmpty ? 'Team RVM' : title,
      body: body,
      imagePath: imagePath,
      payload: jsonEncode({
        'route': _routeFrom(message.data),
        'data': message.data,
      }),
    );
  } catch (error) {
    debugPrint('RVM background push could not be shown: $error');
  }
}

/// Owns the Firebase Messaging lifecycle: permission, token registration with
/// the Scheduler/ESS backend, foreground display (including the image sent from
/// the Firebase console) and tap routing.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;
  bool _signedIn = false;
  String? _token;
  String? _pendingRoute;

  /// Initialise once at startup, after GetIt/session are configured. Every
  /// failure is swallowed: a device without Play services still runs.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      await ensureFirebase();
    } catch (error) {
      debugPrint('RVM push unavailable: Firebase did not initialise ($error)');
      return;
    }

    // Messaging is best-effort: an unsupported platform or a missing Play
    // service must never surface as an app error.
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await _prepareLocalNotifications();

      try {
        await messaging.setAutoInitEnabled(true);
      } catch (_) {
        // Android < 19 / unsupported platform: nothing to do.
      }

      // We draw foreground messages ourselves (needed for the BigPicture style
      // and so Android does not silently drop them while the app is open).
      try {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );
      } catch (_) {
        // iOS only; Android ignores it.
      }

      await _createAndroidChannel();
      // Ask once the first frame is drawn: Android 13 shows the runtime dialog
      // and iOS needs a live view controller for the system prompt.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_requestPermission(messaging));
      });

      _token = await _safeToken(messaging);

      // The backend sends with the classic FCM registration token, so keep using
      // the token API. firebase_messaging 17 also offers `register()`/FID, which
      // the current `/push-devices` contract does not understand yet.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((token) {
        _token = token;
        if (_signedIn) unawaited(registerPushToken(token));
      });

      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForeground(message));
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);

      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromMessage(initial);

      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _openPayload(launch?.notificationResponse?.payload);
      }
    } catch (error) {
      debugPrint('RVM push setup failed: $error');
    }
  }

  /// Call once the user is signed in: a token is only useful to us when the
  /// backend can attach it to an employee, and `/push-devices` needs the JWT.
  Future<void> onSignedIn() async {
    await init();
    _signedIn = true;
    final token = _token ?? await _safeToken(FirebaseMessaging.instance);
    if (token != null && token.isNotEmpty) {
      _token = token;
      await registerPushToken(token);
    }
    _flushPendingRoute();
  }

  Future<void> _prepareLocalNotifications() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        _openPayload(response.payload);
      },
    );
  }

  Future<void> _requestPermission(FirebaseMessaging messaging) async {
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (error) {
      debugPrint('RVM push permission request failed: $error');
    }
  }

  Future<void> _createAndroidChannel() async {
    if (!_isAndroid) return;
    try {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              notificationChannelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (error) {
      debugPrint('RVM notification channel could not be created: $error');
    }
  }

  Future<String?> _safeToken(FirebaseMessaging messaging) async {
    try {
      // Classic FCM registration token — what `/push-devices` expects.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (kDebugMode && token != null && token.isNotEmpty) {
        // Paste this in Firebase Console → Cloud Messaging → Send test message.
        debugPrint('RVM FCM token: $token');
      }
      return token;
    } catch (error) {
      debugPrint('RVM push token unavailable: $error');
      return null;
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final title =
        _text(notification?.title ?? data['title'] ?? data['subject']);
    final body = _text(notification?.body ?? data['body'] ?? data['message']);
    if (title.isEmpty && body.isEmpty) return;

    final imagePath = await _downloadImage(_imageUrlOf(message));
    await _showNotification(
      _local,
      id: _idFor(message),
      title: title.isEmpty ? 'Team RVM' : title,
      body: body,
      imagePath: imagePath,
      payload: jsonEncode({'route': _routeFrom(data), 'data': data}),
    );
  }

  void _openFromMessage(RemoteMessage message) {
    _openPayload(jsonEncode({
      'route': _routeFrom(message.data),
      'data': message.data,
    }));
  }

  void _openPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      _queueRoute('/notifications');
      return;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _queueRoute(_routeFrom(Map<String, dynamic>.from(decoded)));
        return;
      }
    } catch (_) {
      // A plain-text payload may already be a route.
      if (payload.startsWith('/')) {
        _queueRoute(payload);
        return;
      }
    }
    _queueRoute('/notifications');
  }

  void _queueRoute(String route) {
    _pendingRoute = route.isEmpty ? '/notifications' : route;
    _flushPendingRoute();
  }

  void _flushPendingRoute() {
    final route = _pendingRoute;
    if (route == null) return;
    if (!getIt.isRegistered<TeamAuthBloc>()) return;
    if (getIt<TeamAuthBloc>().state.status != TeamAuthStatus.authenticated) {
      // Keep it until sign-in completes; the router would redirect us to /login
      // and the destination would be lost.
      return;
    }
    // Claim the route now so a second flush (init + sign-in both fire at cold
    // start) cannot navigate twice. Restore it if the navigator is not built.
    _pendingRoute = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        _pendingRoute ??= route;
        return;
      }
      try {
        GoRouter.of(context).go(route);
      } catch (error) {
        debugPrint('RVM push route "$route" could not be opened: $error');
      }
    });
  }
}

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String _text(Object? value) => (value ?? '').toString().trim();

int _idFor(RemoteMessage message) =>
    (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) &
    0x7fffffff;

String? _imageUrlOf(RemoteMessage message) {
  final fromNotification = message.notification?.android?.imageUrl ??
      message.notification?.apple?.imageUrl;
  final fromData = message.data['image'] ?? message.data['image_url'];
  final url = _text(fromNotification ?? fromData);
  return url.isEmpty ? null : url;
}

String _routeFrom(Map<String, dynamic> data) {
  for (final key in const ['route', 'link', 'url', 'deep_link', 'screen']) {
    final value = _text(data[key]);
    if (value.isEmpty) continue;
    if (value.startsWith('/')) return value;
    final uri = Uri.tryParse(value);
    if (uri != null && uri.path.isNotEmpty && uri.path.startsWith('/')) {
      return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    }
  }
  return '/notifications';
}

Future<void> _showNotification(
  FlutterLocalNotificationsPlugin plugin, {
  required int id,
  required String title,
  required String body,
  required String? imagePath,
  required String payload,
}) async {
  StyleInformation? style;
  // Without a push image, show the Team RVM launcher icon on the right so the
  // alert is recognisably ours (the small status-bar icon is the white mark).
  AndroidBitmap<Object> largeIcon =
      const DrawableResourceAndroidBitmap('ic_notification_large');
  if (imagePath != null) {
    final bitmap = FilePathAndroidBitmap(imagePath);
    largeIcon = bitmap;
    style = BigPictureStyleInformation(
      bitmap,
      largeIcon: bitmap,
      contentTitle: title,
      summaryText: body,
    );
  }

  final details = NotificationDetails(
    android: AndroidNotificationDetails(
      notificationChannelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_notification',
      color: const Color(0xFF35120C),
      largeIcon: largeIcon,
      styleInformation: style,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
      attachments:
          imagePath == null ? null : [DarwinNotificationAttachment(imagePath)],
    ),
  );

  try {
    await plugin.show(id, title, body, details, payload: payload);
  } catch (error) {
    debugPrint('RVM notification could not be shown: $error');
  }
}

/// iOS decides how to decode an attachment from its extension (Android uses
/// the file contents), so keep a real image extension on the temp file.
String _imageExtension(String url) {
  const allowed = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'};
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  final extension = dot == -1 ? '' : path.substring(dot).toLowerCase();
  return allowed.contains(extension) ? extension : '.jpg';
}

Future<String?> _downloadImage(String? url) async {
  if (url == null || url.isEmpty) return null;
  try {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        followRedirects: true,
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) return null;

    final dir = await getTemporaryDirectory();
    final name = url.hashCode.toUnsigned(32).toRadixString(16);
    final path = '${dir.path}/fcm_$name${_imageExtension(url)}';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (error) {
    debugPrint('RVM notification image could not be downloaded: $error');
    return null;
  }
}
