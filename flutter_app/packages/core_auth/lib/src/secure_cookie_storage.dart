import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_store.dart';

/// Backs cookie_jar's [PersistCookieJar] with encrypted secure storage so the
/// JobPortal `rvm_session` cookie survives app restarts.
class SecureCookieStorage implements Storage {
  SecureCookieStorage([FlutterSecureStorage? storage])
      : _store = SecureStore(storage);

  final SecureStore _store;
  static const _prefix = 'cookie__';

  String _k(String key) => '$_prefix$key';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) => _store.read(key: _k(key));

  @override
  Future<void> write(String key, String value) =>
      _store.write(key: _k(key), value: value);

  @override
  Future<void> delete(String key) => _store.delete(key: _k(key));

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await _store.delete(key: _k(key));
    }
  }
}
