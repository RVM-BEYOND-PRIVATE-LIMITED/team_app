import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAuthDs extends Mock implements AuthRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Parse.passwordAuthResult', () {
    test('active candidate → not banned, carries redirectTo', () {
      final r = Parse.passwordAuthResult(
          {'user_id': 'u1', 'role': 'candidate', 'redirectTo': '/candidate/dashboard'});
      expect(r.banned, isFalse);
      expect(r.userId, 'u1');
      expect(r.redirectTo, '/candidate/dashboard');
    });

    test('banned candidate → banned true (+ redirect alias)', () {
      final r = Parse.passwordAuthResult(
          {'banned': true, 'ban_type': 'hard', 'redirect': '/candidate/banned'});
      expect(r.banned, isTrue);
      expect(r.banType, 'hard');
      expect(r.redirectTo, '/candidate/banned');
    });

    test('reset/setup set for a banned user (redirectTo=/candidate/banned, no banned flag) → banned true', () {
      // reset/set & setup/set do NOT send `banned`; only redirectTo signals it.
      final r = Parse.passwordAuthResult(
          {'user_id': 'u9', 'role': 'candidate', 'redirectTo': '/candidate/banned'});
      expect(r.banned, isTrue);
    });
  });

  group('AuthRepository password methods', () {
    late _MockAuthDs ds;
    late _MockConnectivity conn;
    late AuthRepository repo;
    setUp(() {
      ds = _MockAuthDs();
      conn = _MockConnectivity();
      repo = AuthRepository(remote: ds, connectivity: conn);
    });

    test('online → passwordLogin returns the result', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.passwordLogin(identifier: any(named: 'identifier'), password: any(named: 'password')))
          .thenAnswer((_) async => const PasswordAuthResult(userId: 'u1'));
      final r = await repo.passwordLogin(identifier: 'a@b.com', password: 'secret1');
      expect(r.userId, 'u1');
    });

    test('offline → passwordLogin never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.passwordLogin(identifier: 'a@b.com', password: 'x'),
        throwsA(isA<NoConnectionFailure>()),
      );
      verifyNever(() => ds.passwordLogin(identifier: any(named: 'identifier'), password: any(named: 'password')));
    });

    test('online → resetRequestOtp returns the masked phone', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.resetRequestOtp(any())).thenAnswer((_) async => '+91 ******3210');
      expect(await repo.resetRequestOtp('a@b.com'), '+91 ******3210');
    });

    test('online → setupSet returns the result', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.setupSet(password: any(named: 'password'), confirmPassword: any(named: 'confirmPassword')))
          .thenAnswer((_) async => const PasswordAuthResult(userId: 'u2'));
      final r = await repo.setupSet(password: 'Passw0rd', confirmPassword: 'Passw0rd');
      expect(r.userId, 'u2');
    });

    test('offline → resetVerifyOtp throws NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.resetVerifyOtp('123456'), throwsA(isA<NoConnectionFailure>()));
    });

    test('offline → setupSet never touches the data source (setup path guarded too)', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.setupSet(password: 'Passw0rd', confirmPassword: 'Passw0rd'),
        throwsA(isA<NoConnectionFailure>()),
      );
      verifyNever(() => ds.setupSet(
          password: any(named: 'password'), confirmPassword: any(named: 'confirmPassword')));
    });
  });
}
