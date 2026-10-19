import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements AnnouncementsRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements AnnouncementDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Announcement parser', () {
    test('reads scope→category, message→body, joined batch name', () {
      final list = Parse.announcements([
        {
          'id': 'a1',
          'title': 'Holiday',
          'scope': 'all',
          'message': 'Closed Friday',
          'created_at': '2026-07-01T09:00:00Z',
        },
        {
          'id': 'a2',
          'title': 'Extra class',
          'scope': 'batch',
          'message': 'Sat 10am',
          'batch_id': 'b7',
          'batch': {'name': 'Morning Java'},
        },
      ]);
      expect(list.first.category, AnnouncementCategory.institute);
      expect(list.first.body, 'Closed Friday');
      expect(list.first.isBatchScoped, isFalse);
      expect(list.last.isBatchScoped, isTrue);
      expect(list.last.batchName, 'Morning Java');
    });
  });

  group('AnnouncementDraft toJson', () {
    test('batch scope includes batch_id', () {
      expect(
        const AnnouncementDraft(title: 'T', message: 'M', scope: 'batch', batchId: 'b7').toJson(),
        {'title': 'T', 'message': 'M', 'scope': 'batch', 'batch_id': 'b7'},
      );
    });

    test('all scope omits batch_id even if one is set', () {
      final j = const AnnouncementDraft(title: 'T', message: 'M', scope: 'all', batchId: 'b7').toJson();
      expect(j.containsKey('batch_id'), isFalse);
      expect(j['scope'], 'all');
    });
  });

  group('AnnouncementsRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late AnnouncementsRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = AnnouncementsRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('delete forwards id', () async {
      when(() => ds.delete(any())).thenAnswer((_) async {});
      await repo.delete('a1');
      verify(() => ds.delete('a1')).called(1);
    });

    test('offline → NoConnectionFailure, data source untouched', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.create(const AnnouncementDraft(title: 'T', message: 'M', scope: 'all')),
          throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.create(any()));
    });
  });
}
