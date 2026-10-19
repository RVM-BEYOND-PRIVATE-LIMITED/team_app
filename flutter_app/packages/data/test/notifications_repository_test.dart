import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDataSource extends Mock implements NotificationsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  late _MockDataSource ds;
  late _MockConnectivity conn;
  late NotificationsRepository repo;

  setUp(() {
    ds = _MockDataSource();
    conn = _MockConnectivity();
    repo = NotificationsRepository(remote: ds, connectivity: conn);
  });

  test('online → returns the unread count', () async {
    when(() => conn.isOnline).thenAnswer((_) async => true);
    when(() => ds.unreadCount()).thenAnswer((_) async => 5);
    expect(await repo.unreadCount(), 5);
  });

  test('offline → NoConnectionFailure, data source untouched', () async {
    when(() => conn.isOnline).thenAnswer((_) async => false);
    await expectLater(repo.unreadCount(), throwsA(isA<NoConnectionFailure>()));
    verifyNever(() => ds.unreadCount());
  });
}
