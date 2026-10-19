import 'package:core_network/core_network.dart';

/// Mixed into repositories so every call fails fast with the real cause when
/// the device is offline (reachability-confirmed), instead of waiting for a
/// socket timeout. Data-source [Failure]s otherwise propagate untouched.
mixin ConnectivityGuard {
  ConnectivityService get connectivity;

  Future<void> ensureOnline() async {
    if (!await connectivity.isOnline) throw const NoConnectionFailure();
  }
}
