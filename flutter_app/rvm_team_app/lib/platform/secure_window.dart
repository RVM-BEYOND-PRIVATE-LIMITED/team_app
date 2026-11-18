import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_crash.dart';

/// The window's screenshot block (team_app #52, item 1): Android's
/// `FLAG_SECURE`, set and cleared by MainActivity on the
/// `team_rvm/secure_window` channel. While it is on, screenshots and screen
/// recordings come out black and the app-switcher preview is blank.
///
/// The flag covers the whole window, and more than one screen can need it at
/// once (a sensitive screen pushed over a sensitive tab, or two sensitive
/// screens during a transition). So it is counted: the first [acquire] turns it
/// on and the last [release] turns it off. Screens use it through
/// `SecureScope`, never directly.
///
/// Android only. iOS has no such flag, so elsewhere the count is kept and
/// nothing is sent.
class SecureWindow {
  SecureWindow({MethodChannel? channel, bool Function()? supported})
      : _channel = channel ?? const MethodChannel(channelName),
        _supported = supported ?? _isAndroid;

  /// The app's one window.
  static final SecureWindow instance = SecureWindow();

  /// The channel MainActivity.kt answers.
  static const channelName = 'team_rvm/secure_window';

  final MethodChannel _channel;
  final bool Function() _supported;
  int _holders = 0;

  /// How many screens hold the block now.
  int get holders => _holders;

  /// True while at least one screen holds the block.
  bool get isOn => _holders > 0;

  /// One more screen needs the block; the first one turns it on.
  void acquire() {
    _holders++;
    if (_holders == 1) _send('enable');
  }

  /// A screen no longer needs the block; the last one turns it off.
  void release() {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) _send('disable');
  }

  static bool _isAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _send(String method) async {
    if (!_supported()) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No handler on this host (an engine without MainActivity): there is no
      // window flag to set.
    } catch (e, st) {
      await CrashReporter.record(e, st, reason: 'secure_window:$method');
    }
  }
}
