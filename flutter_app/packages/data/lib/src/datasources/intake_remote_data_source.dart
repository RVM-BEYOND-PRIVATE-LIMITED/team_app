import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Scheduler admission-intake worklist over the Bearer-JWT Dio. Staff list the
/// pending enquiries, fetch the admission prefill, and finalize the undertaking.
/// Ticket CREATION is the public enquiry form (deferred in mobile) and the
/// separate `:id/files` multipart ID-upload needs a file picker (also deferred).
class IntakeRemoteDataSource with DioExecutor {
  IntakeRemoteDataSource(this._dio);

  final Dio _dio;

  /// GET /intakes — pending intakes (already-admitted phones filtered out).
  /// (The Scheduler mounts this router at `/api/intakes` — plural.)
  Future<List<Intake>> list() =>
      guard(() async => Parse.intakes((await _dio.get('/intakes')).data));

  /// GET /intakes/by-phone/:phone — the candidate's own intake status (app
  /// admission gate). Public + scoped to the single phone.
  Future<AdmissionIntakeStatus> statusByPhone(String phone) => guard(
      () async => Parse.admissionIntakeStatus((await _dio.get('/intakes/by-phone/$phone')).data));

  /// GET /intakes/:id/proceed — the admission-form prefill for this intake.
  Future<IntakePrefill> proceed(String id) =>
      guard(() async => Parse.intakePrefill((await _dio.get('/intakes/$id/proceed')).data));

  /// PUT /intakes/:id/finalize — mark the undertaking complete + submit. The
  /// backend requires all three flags true (400 otherwise).
  Future<void> finalize(String id) => guard(() async {
        await _dio.put('/intakes/$id/finalize', data: {
          'video_completed': true,
          'contacts_acknowledged': true,
          'terms_accepted': true,
        });
      });

  /// POST /intakes — create/reuse an enquiry. Returns `(intakeId, reused)`.
  Future<(String, bool)> create(IntakeDraft draft) => guard(
      () async => Parse.intakeCreateResult((await _dio.post('/intakes', data: draft.toJson())).data));

  /// POST /intakes/:id/files — multipart upload of identification files. The
  /// backend route uses `upload.array('files')`, so every part is keyed `files`.
  Future<void> uploadFiles(String id, List<UploadFile> files) => guard(() async {
        final form = FormData();
        for (final f in files) {
          form.files.add(MapEntry('files', MultipartFile.fromBytes(f.bytes, filename: f.name)));
        }
        await _dio.post('/intakes/$id/files', data: form);
      });
}
