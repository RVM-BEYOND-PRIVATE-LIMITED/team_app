/// Read-only view of the bearer token the Scheduler client needs, plus the
/// hooks the network layer calls when auth fails. Implemented by core_auth so
/// core_network stays free of storage/session concerns (no dependency cycle).
abstract interface class TokenStore {
  /// Current Scheduler access token, or null if signed out.
  Future<String?> readSchedulerToken();

  /// Called when the Scheduler rejects the token (expired / "Please
  /// authenticate" / "No token provided") — clear session, bounce to login.
  ///
  /// [message] is the server's own words when the person's access has ended
  /// (an exited account, a changed password; team_app #52 item 8), for the
  /// sign-in screen to show. Null otherwise.
  Future<void> onUnauthorized({String? message});
}

/// A no-op store, handy for tests / unauthenticated screens.
class NullTokenStore implements TokenStore {
  const NullTokenStore();

  @override
  Future<String?> readSchedulerToken() async => null;

  @override
  Future<void> onUnauthorized({String? message}) async {}
}
