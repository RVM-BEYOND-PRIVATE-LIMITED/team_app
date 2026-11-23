import 'package:flutter/material.dart';

/// True while a popup route (a dialog or a modal bottom sheet) is on screen.
/// The floating Feedback tab hides behind such a route (#153).
final ValueNotifier<bool> feedbackModalOpen = ValueNotifier<bool>(false);

/// True while the app shell is loading or showing its access error (#153).
final ValueNotifier<bool> feedbackShellBlocked = ValueNotifier<bool>(false);

/// True while VersionGate is forcing an update (#153).
final ValueNotifier<bool> feedbackVersionBlocked = ValueNotifier<bool>(false);

/// Tracks popup routes so the floating tab never sits over a dialog or sheet.
class FeedbackModalObserver extends NavigatorObserver {
  int _open = 0;

  void _changed(int delta) {
    _open = (_open + delta).clamp(0, 1 << 30);
    feedbackModalOpen.value = _open > 0;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route is PopupRoute) _changed(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PopupRoute) _changed(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PopupRoute) _changed(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is PopupRoute) _changed(-1);
    if (newRoute is PopupRoute) _changed(1);
  }
}

final feedbackModalObserver = FeedbackModalObserver();
