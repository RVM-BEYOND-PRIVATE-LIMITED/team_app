import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage that can recover from undecryptable data.
///
/// Android keeps the key that protects [FlutterSecureStorage] in the Keystore.
/// The ciphertext lives in SharedPreferences, and auto-backup / device transfer
/// can restore that ciphertext without the Keystore key (or the key can be
/// invalidated by an OS event). The plugin then throws
/// `PlatformException(... BadPaddingException ... BAD_DECRYPT ...)` on read:
/// the bytes can never be decrypted, so the only valid recovery is to discard
/// the stale secure store and let the user sign in again. Re-throwing here
/// would make every launch crash on the splash screen (issue d7dcf079).
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read({required String key}) =>
      _recover(() => _storage.read(key: key));

  Future<void> write({required String key, required String value}) =>
      _recover(() => _storage.write(key: key, value: value));

  Future<void> delete({required String key}) =>
      _recover(() => _storage.delete(key: key));

  Future<void> deleteAll() => _recover(() => _storage.deleteAll());

  Future<T> _recover<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error, stack) {
      if (!_isUnreadableCiphertext(error)) rethrow;
      debugPrint('SecureStore: encrypted data cannot be decrypted; '
          'resetting the secure store (${error.message})');
      try {
        await _storage.deleteAll();
      } catch (_) {
        // The reset failed too: surface the original decryption failure, not
        // the cleanup error.
        Error.throwWithStackTrace(error, stack);
      }
      // The corrupt entries are gone; a read now returns null instead of
      // repeatedly failing on the same bytes.
      return operation();
    }
  }

  static bool _isUnreadableCiphertext(PlatformException error) {
    final details = '${error.code} ${error.message} ${error.details}';
    return details.contains('BadPaddingException') ||
        details.contains('BAD_DECRYPT') ||
        details.contains('AEADBadTagException') ||
        details.contains('Tag mismatch');
  }
}
