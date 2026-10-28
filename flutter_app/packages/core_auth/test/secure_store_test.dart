import 'package:core_auth/core_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({this.readError, this.deleteAllError});

  final PlatformException? readError;
  final PlatformException? deleteAllError;

  int reads = 0;
  int deletes = 0;
  bool _reset = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    reads++;
    if (!_reset && readError != null) throw readError!;
    return null;
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes++;
    if (deleteAllError != null) throw deleteAllError!;
    _reset = true;
  }
}

void main() {
  test('clears undecryptable storage and retries the read', () async {
    final storage = _FakeSecureStorage(
      readError: PlatformException(
        code: 'Exception encountered',
        message: 'read',
        details: 'javax.crypto.BadPaddingException: '
            'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
      ),
    );

    expect(await SecureStore(storage).read(key: 'scheduler_token'), isNull);
    expect(storage.deletes, 1);
    expect(storage.reads, 2);
  });

  test('rethrows unrelated platform failures without clearing data', () async {
    final storage = _FakeSecureStorage(
      readError:
          PlatformException(code: 'Exception encountered', message: 'read'),
    );

    await expectLater(
      SecureStore(storage).read(key: 'scheduler_token'),
      throwsA(isA<PlatformException>()),
    );
    expect(storage.deletes, 0);
  });

  test('rethrows the decryption failure when the reset also fails', () async {
    final decryptionError = PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details: 'javax.crypto.BadPaddingException: BAD_DECRYPT',
    );
    final storage = _FakeSecureStorage(
      readError: decryptionError,
      deleteAllError: PlatformException(code: 'reset_failed'),
    );

    await expectLater(
      SecureStore(storage).read(key: 'scheduler_token'),
      throwsA(same(decryptionError)),
    );
    expect(storage.deletes, 1);
  });

  test('splash load survives restored, undecryptable secure storage', () async {
    final storage = _FakeSecureStorage(
      readError: PlatformException(
        code: 'Exception encountered',
        message: 'read',
        details: 'javax.crypto.BadPaddingException: '
            'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
      ),
    );
    final session = AuthSession(storage: storage);

    await session.load();

    expect(session.isSchedulerAuthenticated, isFalse);
    expect(storage.deletes, 1);
  });
}
