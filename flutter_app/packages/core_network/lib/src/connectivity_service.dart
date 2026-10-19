import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Real reachability probe — interface up ≠ internet. Injectable for tests.
typedef ReachabilityProbe = Future<bool> Function();

/// Watches network-interface changes (connectivity_plus) AND confirms actual
/// internet with a lightweight DNS reachability probe. Registered as a service
/// in get_it; blocs/the app watch [onStatusChanged] and can query [isOnline].
class ConnectivityService {
  ConnectivityService({
    Connectivity? connectivity,
    ReachabilityProbe? probe,
  })  : _connectivity = connectivity ?? Connectivity(),
        _probe = probe ?? _dnsProbe;

  final Connectivity _connectivity;
  final ReachabilityProbe _probe;

  /// True only when an interface is up AND the reachability probe succeeds.
  Future<bool> get isOnline async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (_isNone(result)) return false;
      return _probe();
    } catch (_) {
      // Some devices throw a PlatformException from checkConnectivity(). Don't
      // let that block every request (which would hang loaders) — fall back to
      // the bounded reachability probe to decide.
      return _probe();
    }
  }

  /// Emits the current online state on start, then on every interface change
  /// (re-confirming with the probe when an interface is present).
  Stream<bool> onStatusChanged() async* {
    yield await isOnline;
    await for (final result in _connectivity.onConnectivityChanged) {
      yield _isNone(result) ? false : await _probe();
    }
  }

  static bool _isNone(List<ConnectivityResult> r) =>
      r.isEmpty || r.every((e) => e == ConnectivityResult.none);

  /// Default probe: resolve a well-known host with a short timeout. Uses only
  /// the standard INTERNET permission — no sensitive data, Play-safe.
  static Future<bool> _dnsProbe() async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
