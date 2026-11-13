import 'package:core_auth/core_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Secure storage in memory.
class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

/// team_app #52, item 8: the end of a session carries the server's message
/// when the person's access has ended, so the sign-in screen can show it.
void main() {
  test('onUnauthorized signs out and passes the server\'s message on',
      () async {
    final session = AuthSession(storage: _MemoryStorage());
    await session.saveSchedulerSession(token: 'test-token', role: 'faculty');
    final events = <String?>[];
    final sub = session.sessionExpired.listen(events.add);

    await session.onUnauthorized(
        message: 'Your password was changed. Please sign in again.');
    await session.onUnauthorized();
    await Future<void>.delayed(Duration.zero);

    expect(session.isSchedulerAuthenticated, isFalse);
    expect(await session.readSchedulerToken(), isNull);
    expect(events, ['Your password was changed. Please sign in again.', null]);
    await sub.cancel();
    await session.dispose();
  });
}
