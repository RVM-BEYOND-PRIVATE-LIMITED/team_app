import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDataSource extends Mock implements StaffAuthRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  late _MockDataSource ds;
  late _MockConnectivity conn;
  late StaffAuthRepository repo;

  const identity = StaffIdentity(userId: 'u1', role: AppRole.admin, locationId: 1);

  setUp(() {
    ds = _MockDataSource();
    conn = _MockConnectivity();
    repo = StaffAuthRepository(remote: ds, connectivity: conn);
  });

  test('offline → NoConnectionFailure, data source not touched', () async {
    when(() => conn.isOnline).thenAnswer((_) async => false);
    await expectLater(
      repo.login(username: 'a', password: 'b', locationName: 'Pune'),
      throwsA(isA<NoConnectionFailure>()),
    );
    verifyNever(() => ds.login(
        username: any(named: 'username'),
        password: any(named: 'password'),
        locationName: any(named: 'locationName')));
  });

  test('online → returns token + identity', () async {
    when(() => conn.isOnline).thenAnswer((_) async => true);
    when(() => ds.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
            locationName: any(named: 'locationName')))
        .thenAnswer((_) async => const StaffSignedIn(token: 'jwt', identity: identity));
    final res = await repo.login(username: 'a', password: 'b', locationName: 'Pune');
    expect(res, isA<StaffSignedIn>());
    expect((res as StaffSignedIn).token, 'jwt');
    expect(res.identity.role, AppRole.admin);
  });

  test('verifyTwoFactor offline → NoConnectionFailure, data source not touched', () async {
    when(() => conn.isOnline).thenAnswer((_) async => false);
    await expectLater(
      repo.verifyTwoFactor(challengeId: 'c1', code: '123456', locationName: 'Pune'),
      throwsA(isA<NoConnectionFailure>()),
    );
    verifyNever(() => ds.verifyTwoFactor(
        challengeId: any(named: 'challengeId'),
        code: any(named: 'code'),
        locationName: any(named: 'locationName')));
  });

  test('bad credentials (401) propagates as UnauthorizedFailure', () async {
    when(() => conn.isOnline).thenAnswer((_) async => true);
    when(() => ds.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
            locationName: any(named: 'locationName')))
        .thenThrow(const UnauthorizedFailure());
    await expectLater(
      repo.login(username: 'a', password: 'x', locationName: 'Pune'),
      throwsA(isA<UnauthorizedFailure>()),
    );
  });
}
