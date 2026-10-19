import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements UsersRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeProvision extends Fake implements UserProvisionDraft {}

class _FakeUpdate extends Fake implements UserUpdate {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeProvision());
    registerFallbackValue(_FakeUpdate());
  });

  group('Users parser', () {
    test('staffUsers reads the list rows', () {
      final list = Parse.staffUsers([
        {'id': 'u1', 'username': 'ravi', 'phone_number': '999', 'role': 'admin', 'location_id': 2},
      ]);
      expect(list.single.username, 'ravi');
      expect(list.single.role, 'admin');
      expect(list.single.locationId, 2);
    });

    test('staffUserOf unwraps {user:{...}} update envelope + bare provision row', () {
      expect(Parse.staffUserOf({'message': 'ok', 'user': {'id': 'u9', 'username': 'x'}}).id, 'u9');
      expect(Parse.staffUserOf({'id': 'u3', 'username': 'y'}).username, 'y');
    });
  });

  group('Draft toJson', () {
    test('provision omits location for accounts_admin path (null id)', () {
      final j = const UserProvisionDraft(username: 'a', password: 'p', role: 'accounts_admin').toJson();
      expect(j['role'], 'accounts_admin');
      expect(j.containsKey('location_id'), isFalse);
    });

    test('update sends only provided fields, drops empty password', () {
      expect(const UserUpdate(username: 'a', password: '').toJson(), {'username': 'a'});
      expect(const UserUpdate(role: 'faculty', password: 'secret').toJson(), {'role': 'faculty', 'password': 'secret'});
    });

    test('reset-password toJson', () {
      expect(
        const ResetPasswordDraft(username: 'a', phoneNumber: '999', newPassword: 'newpass').toJson(),
        {'username': 'a', 'phone_number': '999', 'new_password': 'newpass'},
      );
    });
  });

  group('UsersRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late UsersRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = UsersRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('assignRole forwards userId + role', () async {
      when(() => ds.assignRole(userId: any(named: 'userId'), role: any(named: 'role'))).thenAnswer((_) async {});
      await repo.assignRole(userId: 'u1', role: 'admin');
      verify(() => ds.assignRole(userId: 'u1', role: 'admin')).called(1);
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.delete(any()));
    });
  });
}
