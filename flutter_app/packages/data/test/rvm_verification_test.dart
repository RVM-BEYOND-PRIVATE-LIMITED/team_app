import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockCareerDs extends Mock implements CareerRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  group('Parse.rvmVerificationStatus', () {
    test('feature OFF → featureEnabled false, no verification, cannot submit', () {
      final s = Parse.rvmVerificationStatus({'verification': null, 'feature_enabled': false});
      expect(s.featureEnabled, isFalse);
      expect(s.verification, isNull);
      expect(s.canSubmit, isFalse);
    });

    test('feature ON + pending record → maps fields, canSubmit false', () {
      final s = Parse.rvmVerificationStatus({
        'feature_enabled': true,
        'verification': {
          'id': 'v1',
          'status': 'pending_review',
          'training_start_date': '2025-01-01',
          'training_end_date': '2025-06-01',
          'industry': 'Aerospace',
          'job_role': 'CAD Designer',
          'skills': ['AutoCAD', 'GD&T'],
          'certificate_file_name': 'cert.pdf',
        },
      });
      expect(s.featureEnabled, isTrue);
      expect(s.verification!.isPending, isTrue);
      expect(s.verification!.skills, ['AutoCAD', 'GD&T']);
      expect(s.canSubmit, isFalse);
    });

    test('feature ON + rejected record → canSubmit true (may resubmit)', () {
      final s = Parse.rvmVerificationStatus({
        'feature_enabled': true,
        'verification': {'id': 'v2', 'status': 'rejected', 'rejection_reason': 'Blurry scan'},
      });
      expect(s.verification!.isRejected, isTrue);
      expect(s.canSubmit, isTrue);
    });
  });

  group('CareerRepository.rvmVerification', () {
    late _MockCareerDs ds;
    late _MockConnectivity conn;
    late CareerRepository repo;
    setUp(() {
      ds = _MockCareerDs();
      conn = _MockConnectivity();
      repo = CareerRepository(remote: ds, connectivity: conn);
    });

    test('online → returns the status', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.rvmVerification())
          .thenAnswer((_) async => const RvmVerificationStatus(featureEnabled: true));
      expect((await repo.rvmVerification()).featureEnabled, isTrue);
    });

    test('offline → rvmVerification throws NoConnectionFailure', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.rvmVerification(), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.rvmVerification());
    });

    test('offline → submit throws NoConnectionFailure before uploading', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.submitRvmVerification(
          trainingStartDate: '2025-01-01',
          trainingEndDate: '2025-06-01',
          industry: 'X',
          jobDomain: 'Y',
          jobRole: 'Z',
          skills: const ['A'],
          certificateBytes: const [1, 2],
          certificateName: 'c.pdf',
        ),
        throwsA(isA<NoConnectionFailure>()),
      );
    });
  });
}
