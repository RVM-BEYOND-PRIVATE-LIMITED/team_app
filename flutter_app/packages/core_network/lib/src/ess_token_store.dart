/// The Team RVM ESS "kept sign-in" (task A3): a rotating, install-bound
/// refresh token that outlives the Scheduler access token. Implemented by
/// core_auth so this HTTP layer stays free of storage concerns.
///
/// The access token itself is kept in the same slot as the Scheduler token,
/// because the ESS mints it in the Scheduler's own format and it is accepted by
/// both hosts. This interface only carries what is unique to the ESS.
abstract interface class EssTokenStore {
  /// The opaque refresh token, or null before the first exchange.
  Future<String?> readEssRefreshToken();

  /// A stable per-install identifier, generated once and never cleared by a
  /// sign-out (the server binds a refresh family to it).
  Future<String> installId();

  /// Persist the result of `POST /api/ess/session` or `/session/refresh`.
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  });

  /// Drop the ESS session (a refused refresh, or a real sign-out).
  Future<void> clearEssSession();
}

/// A no-op store, handy for tests / unauthenticated screens.
class NullEssTokenStore implements EssTokenStore {
  const NullEssTokenStore();

  @override
  Future<String?> readEssRefreshToken() async => null;

  @override
  Future<String> installId() async => 'test-install';

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async {}

  @override
  Future<void> clearEssSession() async {}
}
