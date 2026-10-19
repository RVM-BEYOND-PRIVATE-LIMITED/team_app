import 'dart:convert';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// Captures the outgoing request and returns a canned JSON body, so we can
/// assert what the data source actually put on the wire (multipart parts,
/// query params) without a live backend.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;
  final Map<String, dynamic> body;
  _CapturingAdapter(this.body);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured = options;
    // Drain the multipart body so FormData is fully finalized before we inspect.
    if (requestStream != null) await requestStream.drain<void>();
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_CapturingAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://test.local'))..httpClientAdapter = adapter;

void main() {
  group('CareerRemoteDataSource.addCertification multipart', () {
    test('sends text fields + a file part keyed "certificate" with content-type', () async {
      final adapter = _CapturingAdapter({'id': 'c1', 'has_certificate': true});
      final ds = CareerRemoteDataSource(_dioWith(adapter));

      final id = await ds.addCertification(
        name: 'AutoCAD Pro',
        issuingAuthority: 'Autodesk',
        issueDate: '2025-08',
        durationMonths: 24,
        fileBytes: [1, 2, 3, 4],
        fileName: 'cert.pdf',
      );

      expect(id, 'c1');
      final form = adapter.captured!.data as FormData;
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['name'], 'AutoCAD Pro');
      expect(fields['issuing_authority'], 'Autodesk');
      expect(fields['issue_date'], '2025-08');
      expect(fields['duration_months'], '24');

      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'certificate');
      expect(form.files.single.value.filename, 'cert.pdf');
      expect(form.files.single.value.contentType?.mimeType, 'application/pdf');
    });

    test('omits the file part when no file is attached', () async {
      final adapter = _CapturingAdapter({'id': 'c2', 'has_certificate': false});
      final ds = CareerRemoteDataSource(_dioWith(adapter));

      await ds.addCertification(name: 'No-file cert');

      final form = adapter.captured!.data as FormData;
      expect(form.files, isEmpty);
      expect({for (final f in form.fields) f.key: f.value}, {'name': 'No-file cert'});
    });
  });

  group('FeedbackRemoteDataSource.myFeedback', () {
    test('forwards the page query param and parses {items:[...]}', () async {
      final adapter = _CapturingAdapter({
        'items': [
          {'id': 'f1', 'feedback_type': 'bug', 'title': 'Crash'}
        ],
      });
      final ds = FeedbackRemoteDataSource(_dioWith(adapter));

      final items = await ds.myFeedback(page: 3);
      expect(items.single.id, 'f1');
      expect(adapter.captured!.uri.queryParameters['page'], '3');
    });
  });

  group('CareerRemoteDataSource.submitRvmVerification multipart', () {
    test('sends text fields, skills as a JSON array string, and a certificate file', () async {
      final adapter = _CapturingAdapter({'id': 'v1', 'status': 'pending_review'});
      final ds = CareerRemoteDataSource(_dioWith(adapter));

      final status = await ds.submitRvmVerification(
        trainingStartDate: '2025-01-01',
        trainingEndDate: '2025-06-01',
        industry: 'Aerospace',
        jobDomain: 'CAD',
        jobRole: 'Designer',
        skills: const ['CNC', 'Lean'],
        certificateBytes: const [1, 2, 3],
        certificateName: 'cert.pdf',
      );

      expect(status, 'pending_review');
      final form = adapter.captured!.data as FormData;
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['training_start_date'], '2025-01-01');
      expect(fields['job_role'], 'Designer');
      expect(fields['skills'], '["CNC","Lean"]'); // JSON array string
      expect(form.files.single.key, 'certificate');
      expect(form.files.single.value.contentType?.mimeType, 'application/pdf');
    });
  });

  group('FeedbackRemoteDataSource.uploadScreenshot multipart', () {
    test('sends the image keyed "file" with an image content-type', () async {
      final adapter = _CapturingAdapter({'storage_path': 'shots/x.png'});
      final ds = FeedbackRemoteDataSource(_dioWith(adapter));

      final path = await ds.uploadScreenshot([9, 9, 9], 'shot.png');
      expect(path, 'shots/x.png');
      final form = adapter.captured!.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.contentType?.mimeType, 'image/png');
    });
  });
}
