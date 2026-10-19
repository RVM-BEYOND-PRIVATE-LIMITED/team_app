import 'package:core_network/core_network.dart';

/// Fails a request fast with [NoConnectionFailure] when the device is really
/// offline (interface up is not enough — the service confirms reachability).
mixin ConnectivityGuard {
  ConnectivityService get connectivity;

  Future<void> ensureOnline() async {
    if (!await connectivity.isOnline) throw const NoConnectionFailure();
  }
}
