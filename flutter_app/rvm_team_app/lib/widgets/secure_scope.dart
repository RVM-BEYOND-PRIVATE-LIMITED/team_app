import 'package:flutter/widgets.dart';

import '../platform/secure_window.dart';

/// Blocks screenshots while [child] is on screen (team_app #52, item 1).
///
/// It holds the window's block ([SecureWindow]) only while its route is the
/// one on screen:
///  * on from its first frame, and through its own push and pop animations,
///    while the screen can still be seen;
///  * still on under a dialog or a bottom sheet, which leave the screen
///    visible behind them;
///  * off once an opaque route has covered it (the Navigator stops the tickers
///    of a route nobody can see), and on again when that route is popped;
///  * off while [enabled] is false, which is how a shell tab says it is not
///    the selected one (an IndexedStack keeps every opened tab built);
///  * off when it leaves the tree.
///
/// Scopes are counted, so a sensitive screen pushed over a sensitive tab, or
/// two sensitive screens crossing in a transition, never drop the block in
/// between, and a screen that is not sensitive never turns it on.
class SecureScope extends StatefulWidget {
  const SecureScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.window,
  });

  final Widget child;

  /// False keeps the window as it is. A shell tab passes "is selected".
  final bool enabled;

  /// The window to hold; [SecureWindow.instance] unless a test passes one.
  final SecureWindow? window;

  @override
  State<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends State<SecureScope> {
  /// The window this scope holds the block on, or null while it holds none.
  SecureWindow? _held;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant SecureScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _hold(null);
    super.dispose();
  }

  /// TickerMode is false for a route an opaque route covers, so reading it
  /// also rebuilds this scope when that changes.
  void _sync() => _hold(widget.enabled && TickerMode.of(context)
      ? (widget.window ?? SecureWindow.instance)
      : null);

  void _hold(SecureWindow? window) {
    if (identical(window, _held)) return;
    _held?.release();
    _held = window;
    window?.acquire();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
