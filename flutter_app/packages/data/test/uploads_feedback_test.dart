import 'package:core_network/core_network.dart';
import 'package:data/data.dart';
import 'package:data/src/datasources/multipart.dart';
import 'package:domain/domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockCareerDs extends Mock implements CareerRemoteDataSource {}

class _MockFeedbackDs extends Mock implements FeedbackRemoteDataSource {}

class _MockConnectivity extends Mock implements ConnectivityService {}

void main() {
  setUpAll(() {
    registerFallbackValue(const FeedbackDraft(
        type: FeedbackType.bug, title: 't', description: 'desc long enough'));
  });

  group('Certification + feedback parsers', () {
    test('certifications reads {certifications:[...]}; has_certificate from signed_url', () {
      final list = Parse.certifications({
        'certifications': [
          {
            'id': 'c1',
            'name': 'AutoCAD Pro',
            'issuing_authority': 'Autodesk',
            'issue_date': '2025-08',
            'duration_months': 24,
            'signed_url': 'https://x/y.pdf',
            'created_at': '2026-01-01',
          },
          {'id': 'c2', 'name': 'No file cert'},
        ],
      });
      expect(list, hasLength(2));
      expect(list[0].name, 'AutoCAD Pro');
      expect(list[0].hasCertificate, isTrue); // signed_url present
      expect(list[0].issueDate, '2025-08');
      expect(list[1].hasCertificate, isFalse);
    });

    test('feedbackItems reads {items:[...]} + maps type', () {
      final list = Parse.feedbackItems({
        'items': [
          {'id': 'f1', 'feedback_type': 'feature_request', 'title': 'Dark mode', 'status': 'reviewing'}
        ],
      });
      expect(list.single.type, FeedbackType.featureRequest);
      expect(list.single.title, 'Dark mode');
      expect(list.single.status, 'reviewing');
    });

    test('feedbackItems tolerates empty, bare-list and missing-key shapes', () {
      expect(Parse.feedbackItems({'items': const []}), isEmpty);
      expect(Parse.feedbackItems(const []), isEmpty);
      expect(Parse.feedbackItems({'total': 0}), isEmpty); // no `items` key
      expect(
        Parse.feedbackItems([
          {'id': 'f2', 'feedback_type': 'weird_unknown', 'title': 'X'}
        ]).single.type,
        FeedbackType.other, // unknown type → other
      );
    });
  });

  group('multipart content-type', () {
    test('mediaTypeFor maps extensions to MIME (needed by the avatar endpoint)', () {
      expect(mediaTypeFor('resume.pdf')?.mimeType, 'application/pdf');
      expect(mediaTypeFor('a.JPG')?.mimeType, 'image/jpeg');
      expect(mediaTypeFor('a.jpeg')?.mimeType, 'image/jpeg');
      expect(mediaTypeFor('a.png')?.mimeType, 'image/png');
      expect(mediaTypeFor('a.webp')?.mimeType, 'image/webp');
      expect(mediaTypeFor('noext'), isNull);
    });

    test('multipartFromBytes carries filename + content-type', () {
      final part = multipartFromBytes([1, 2, 3], 'photo.png');
      expect(part.filename, 'photo.png');
      expect(part.contentType?.mimeType, 'image/png');
    });
  });

  group('CareerRepository uploads', () {
    late _MockCareerDs ds;
    late _MockConnectivity conn;
    late CareerRepository repo;
    setUp(() {
      ds = _MockCareerDs();
      conn = _MockConnectivity();
      repo = CareerRepository(remote: ds, connectivity: conn);
    });

    test('online → returns certifications', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.certifications())
          .thenAnswer((_) async => const [Certification(id: 'c1', name: 'X')]);
      expect((await repo.certifications()).single.id, 'c1');
    });

    test('offline → uploadResume never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.uploadResume([1, 2], 'r.pdf'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.uploadResume(any(), any()));
    });

    test('offline → addCertification never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(repo.addCertification(name: 'X'), throwsA(isA<NoConnectionFailure>()));
      verifyNever(() => ds.addCertification(name: any(named: 'name')));
    });
  });

  group('FeedbackRepository', () {
    late _MockFeedbackDs ds;
    late _MockConnectivity conn;
    late FeedbackRepository repo;
    setUp(() {
      ds = _MockFeedbackDs();
      conn = _MockConnectivity();
      repo = FeedbackRepository(remote: ds, connectivity: conn);
    });

    test('online → submit returns new id', () async {
      when(() => conn.isOnline).thenAnswer((_) async => true);
      when(() => ds.submit(any())).thenAnswer((_) async => 'fb-1');
      final id = await repo.submit(const FeedbackDraft(
          type: FeedbackType.bug, title: 'Crash', description: 'It crashes on open'));
      expect(id, 'fb-1');
    });

    test('offline → submit never touches the data source', () async {
      when(() => conn.isOnline).thenAnswer((_) async => false);
      await expectLater(
        repo.submit(const FeedbackDraft(type: FeedbackType.bug, title: 'x', description: 'yyyyyyyyyy')),
        throwsA(isA<NoConnectionFailure>()),
      );
      verifyNever(() => ds.submit(any()));
    });
  });

  group('FeedbackDraft serialization', () {
    test('maps type to wire value + omits null screenshot', () {
      final json = const FeedbackDraft(
              type: FeedbackType.featureRequest, title: 'T', description: 'Desc here ok')
          .toJson();
      expect(json['feedback_type'], 'feature_request');
      expect(json.containsKey('screenshot_storage_path'), isFalse);
    });

    test('includes screenshot path when present', () {
      final json = const FeedbackDraft(
              type: FeedbackType.bug, title: 'T', description: 'Desc here ok', screenshotStoragePath: 'p/x.png')
          .toJson();
      expect(json['screenshot_storage_path'], 'p/x.png');
    });
  });
}
