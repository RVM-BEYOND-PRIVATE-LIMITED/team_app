import 'dart:async';
import 'dart:math';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:core_network/core_network.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_cookie_storage.dart';
import 'secure_store.dart';

/// Plain multi-backend session store (no ChangeNotifier — reactivity lives in
/// the Blocs now). Holds the Scheduler bearer JWT in secure storage, the
/// JobPortal `rvm_session` cookie in a persistent jar, and the Team RVM ESS
/// "kept sign-in" (refresh token + install id). Implements [TokenStore] and
/// [EssTokenStore] so the network layer can read tokens / react to 401.
class AuthSession implements TokenStore, EssTokenStore {
  AuthSession({
    FlutterSecureStorage? storage,
    PersistCookieJar? cookieJar,
    PersistCookieJar? schedulerCookieJar,
  })  : _store = SecureStore(storage),
        cookieJar = cookieJar ??
            PersistCookieJar(storage: SecureCookieStorage(storage)),
        schedulerCookieJar = schedulerCookieJar ??
            PersistCookieJar(storage: SecureCookieStorage(storage));

  final SecureStore _store;

  /// Passed to `DioFactory.jobPortal(...)`.
  final PersistCookieJar cookieJar;

  /// Passed to `DioFactory.scheduler(...)` so the punch device cookie
  /// (`rvm_att_dev`) survives launches (tasks B8/B13). Never cleared on sign-out.
  final PersistCookieJar schedulerCookieJar;

  static const _kSchedulerToken = 'scheduler_token';
  static const _kSchedulerRole = 'scheduler_role';
  static const _kEssRefreshToken = 'ess_refresh_token';
  static const _kEssAccessExpiresAt = 'ess_access_expires_at';
  static const _kEssInstallId = 'ess_install_id';

  String? _schedulerToken;
  String? _schedulerRole;
  String? _essRefreshToken;

  final StreamController<void> _expiredController =
      StreamController<void>.broadcast();

  /// Fires when the network layer hits a 401 ([onUnauthorized]) — the session
  /// has been cleared and the app should route back to login. Blocs listen to
  /// this to react to expiry without polling. (Explicit sign-out does NOT emit.)
  Stream<void> get sessionExpired => _expiredController.stream;

  String? get schedulerRole => _schedulerRole;
  bool get isSchedulerAuthenticated =>
      _schedulerToken != null && _schedulerToken!.isNotEmpty;

  /// Hydrate from storage at app start.
  Future<void> load() async {
    _schedulerToken = await _store.read(key: _kSchedulerToken);
    _schedulerRole = await _store.read(key: _kSchedulerRole);
  }

  /// Persist the Scheduler login result.
  Future<void> saveSchedulerSession(
      {required String token, String? role}) async {
    _schedulerToken = token;
    _schedulerRole = role;
    await _store.write(key: _kSchedulerToken, value: token);
    if (role != null) await _store.write(key: _kSchedulerRole, value: role);
  }

  // --- TokenStore ---------------------------------------------------------

  @override
  Future<String?> readSchedulerToken() async =>
      _schedulerToken ??= await _store.read(key: _kSchedulerToken);

  @override
  Future<void> onUnauthorized() async {
    await signOutScheduler();
    if (!_expiredController.isClosed) _expiredController.add(null);
  }

  // --- EssTokenStore (Team RVM kept sign-in) ------------------------------

  @override
  Future<String?> readEssRefreshToken() async =>
      _essRefreshToken ??= await _store.read(key: _kEssRefreshToken);

  @override
  Future<String> installId() async {
    final existing = await _store.read(key: _kEssInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomInstallId();
    await _store.write(key: _kEssInstallId, value: id);
    return id;
  }

  static String _randomInstallId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<void> saveEssSession({
    required String accessToken,
    required String refreshToken,
    DateTime? accessExpiresAt,
  }) async {
    _essRefreshToken = refreshToken;
    await _store.write(key: _kEssRefreshToken, value: refreshToken);
    if (accessExpiresAt != null) {
      await _store.write(
          key: _kEssAccessExpiresAt, value: accessExpiresAt.toIso8601String());
    }
    // The ESS access token is minted in the Scheduler's own format and is
    // accepted by both hosts, so it becomes the Scheduler token too.
    _schedulerToken = accessToken;
    await _store.write(key: _kSchedulerToken, value: accessToken);
  }

  @override
  Future<void> clearEssSession() async {
    _essRefreshToken = null;
    await _store.delete(key: _kEssRefreshToken);
    await _store.delete(key: _kEssAccessExpiresAt);
  }

  // --- sign out -----------------------------------------------------------

  Future<void> signOutScheduler() async {
    _schedulerToken = null;
    _schedulerRole = null;
    await _store.delete(key: _kSchedulerToken);
    await _store.delete(key: _kSchedulerRole);
  }

  Future<void> signOutJobPortal() => cookieJar.deleteAll();

  Future<void> signOutAll() async {
    await signOutScheduler();
    await clearEssSession();
    await signOutJobPortal();
  }

  Future<void> dispose() => _expiredController.close();
}
