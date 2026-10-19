import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockDs extends Mock implements IntakeRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _FakeDraft extends Fake implements IntakeDraft {}

void main() {
  setUpAll(() => registerFallbackValue(_FakeDraft()));

  group('Intake parser', () {
    test('intake reads flags, courses, file count, status', () {
      final list = Parse.intakes([
        {
          'id': 'i1',
          'student_name': 'Asha',
          'student_phone_number': '9990001112',
          'course_ids': ['c1', 'c2'],
          'fee_amount': 15000,
          'video_completed': true,
          'contacts_acknowledged': false,
          'terms_accepted': false,
          'identification_files': [
            {'file_name': 'id.jpg'}
          ],
          'status': 'draft',
        },
      ]);
      final i = list.single;
      expect(i.studentName, 'Asha');
      expect(i.courseIds, ['c1', 'c2']);
      expect(i.feeAmount, 15000);
      expect(i.videoCompleted, isTrue);
      expect(i.undertakingComplete, isFalse);
      expect(i.identificationFileCount, 1);
      expect(i.isSubmitted, isFalse);
    });

    test('intakePrefill unwraps {prefill:{...}} + maps course_start_date', () {
      final p = Parse.intakePrefill({
        'prefill': {
          'student_name': 'Asha',
          'course_ids': ['c1'],
          'course_start_date': '2026-08-01',
          'location_id': 4,
        }
      });
      expect(p.studentName, 'Asha');
      expect(p.courseIds, ['c1']);
      expect(p.courseStartDate, DateTime(2026, 8, 1));
      expect(p.locationId, 4);
    });

    test('intakeCreateResult reads (id, reused)', () {
      final r = Parse.intakeCreateResult({'intake_id': 'i9', 'reused': true});
      expect(r.$1, 'i9');
      expect(r.$2, isTrue);
    });
  });

  group('IntakeRepository', () {
    late _MockDs ds;
    late _MockConnectivity conn;
    late IntakeRepository repo;

    setUp(() {
      ds = _MockDs();
      conn = _MockConnectivity();
      repo = IntakeRepository(remote: ds, connectivity: conn);
      when(() => conn.isOnline).thenAnswer((_) async => true);
    });

    test('finalize forwards id', () async {
      when(() => ds.finalize(any())).thenAnswer((_) async {});
      await repo.finalize('i1');
      verify(() => ds.finalize('i1')).called(1);
    });

    test('uploadFiles forwards id + files', () async {
      when(() => ds.uploadFiles(any(), any())).thenAnswer((_) async {});
      final files = [const UploadFile(name: 'id.jpg', bytes: [1, 2, 3])];
      await repo.uploadFiles('i1', files);
      verify(() => ds.uploadFiles('i1', files)).called(1);
    });

    test('offline → NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.list(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.list());
    });
  });
}
