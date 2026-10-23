import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The one messenger every screen shares, so an error raised outside a screen's
/// own `BuildContext` (a bloc, a zone, the Flutter framework) can still reach the
/// person as a toast instead of a crash or a silent failure.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The root navigator's overlay. A toast inserted here sits ABOVE a modal
/// bottom sheet or dialog; a ScaffoldMessenger SnackBar sits below them and is
/// invisible while a form is open.
final rootNavigatorKey = GlobalKey<NavigatorState>();

String? _lastMessage;
DateTime? _lastAt;
OverlayEntry? _toast;

/// Show a short, staff-readable message. Identical messages inside two seconds
/// are collapsed so one failed request cannot stack several toasts.
void showAppMessage(String message) {
  final text = message.trim();
  if (text.isEmpty) return;
  final now = DateTime.now();
  // The generic line is a last resort; one unexpected error can repeat every
  // frame. Keep it quiet for 30s instead of re-toasting it every two seconds.
  final window = text.startsWith('Something went wrong')
      ? const Duration(seconds: 30)
      : const Duration(seconds: 2);
  if (_lastMessage == text &&
      _lastAt != null &&
      now.difference(_lastAt!) < window) {
    return;
  }
  _lastMessage = text;
  _lastAt = now;

  // Inserting an OverlayEntry while the tree is being built/laid out makes
  // Flutter report "Build scheduled during frame". Defer to the end of the
  // frame when an error arrives mid-frame.
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _insertToast(text));
    WidgetsBinding.instance.scheduleFrame();
    return;
  }
  _insertToast(text);
}

void _insertToast(String text) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) {
    // Startup: the navigator is not built yet; fall back to the messenger.
    final messenger = rootScaffoldMessengerKey.currentState;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ));
    return;
  }

  if (_toast?.mounted == true) _toast!.remove();
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xEE2B2B2B),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  Timer(const Duration(seconds: 4), () {
    if (_toast == entry) {
      if (entry.mounted) entry.remove();
      _toast = null;
    }
  });
}
