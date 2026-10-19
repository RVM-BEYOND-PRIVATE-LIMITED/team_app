import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';
import 'multipart.dart';

/// Candidate career-profile endpoints over the JobPortal Dio: the work
/// experience stack (CRUD) and the shared skill-tag autocomplete.
class CareerRemoteDataSource with DioExecutor {
  CareerRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<ExperienceEntry>> experienceStack() => guard(
      () async => Parse.experienceStack((await _dio.get('/candidates/experience-stack')).data));

  Future<ExperienceEntry> addExperience(ExperienceDraft draft) => guard(() async =>
      Parse.experienceEntryOf(
          (await _dio.post('/candidates/experience-stack', data: draft.toJson())).data));

  Future<ExperienceEntry> updateExperience(String id, ExperienceDraft draft) => guard(() async =>
      Parse.experienceEntryOf(
          (await _dio.patch('/candidates/experience-stack/$id', data: draft.toJson())).data));

  Future<void> deleteExperience(String id) =>
      guard(() async => _dio.delete('/candidates/experience-stack/$id'));

  Future<List<SkillSuggestion>> skillSuggestions(String query, {String? category}) => guard(() async {
        final q = query.trim();
        if (q.isEmpty) return const <SkillSuggestion>[];
        final res = await _dio.get('/candidates/skill-suggestions', queryParameters: {
          'q': q,
          if (category != null && category.isNotEmpty) 'category': category,
        });
        return Parse.skillSuggestions(res.data);
      });

  // ── Resume (PDF only, ≤5 MB) ────────────────────────────────────────────
  Future<String> uploadResume(List<int> bytes, String filename) => guard(() async {
        final form = FormData()..files.add(MapEntry('resume', multipartFromBytes(bytes, filename)));
        final res = await _dio.post('/candidates/resume', data: form);
        return asMap(res.data)['resume_path']?.toString() ?? '';
      });

  Future<void> deleteResume() => guard(() async => _dio.delete('/candidates/resume'));

  // ── Avatar (jpg/png/webp, ≤2 MB) ────────────────────────────────────────
  Future<String> uploadAvatar(List<int> bytes, String filename) => guard(() async {
        final form = FormData()..files.add(MapEntry('avatar', multipartFromBytes(bytes, filename)));
        final res = await _dio.post('/candidates/avatar', data: form);
        return asMap(res.data)['avatar_path']?.toString() ?? '';
      });

  Future<void> deleteAvatar() => guard(() async => _dio.delete('/candidates/avatar'));

  /// Avatar image BYTES streamed through the backend proxy
  /// (`/candidates/avatar/image`). The device fetches from the backend it
  /// already talks to (never the storage cloud host), so no separate DNS lookup
  /// — and thus no host-lookup SocketException — can occur. 404 (no avatar) is
  /// accepted as a valid status and returns null, so it never throws for the
  /// common "no photo yet" case.
  Future<List<int>?> avatarImage() => guard(() async {
        final res = await _dio.get<List<int>>(
          '/candidates/avatar/image',
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (s) => s == 200 || s == 404,
          ),
        );
        return res.statusCode == 200 ? res.data : null;
      });

  // ── Certifications (optional attached file) ─────────────────────────────
  Future<List<Certification>> certifications() => guard(
      () async => Parse.certifications((await _dio.get('/candidates/certifications')).data));

  /// Returns the new certification id. [fileBytes] optionally attaches a
  /// certificate document (PDF/JPG/PNG).
  Future<String> addCertification({
    required String name,
    String? issuingAuthority,
    String? issueDate,
    int? durationMonths,
    List<int>? fileBytes,
    String? fileName,
  }) =>
      guard(() async {
        final form = FormData();
        form.fields.add(MapEntry('name', name));
        if (issuingAuthority != null && issuingAuthority.isNotEmpty) {
          form.fields.add(MapEntry('issuing_authority', issuingAuthority));
        }
        if (issueDate != null && issueDate.isNotEmpty) {
          form.fields.add(MapEntry('issue_date', issueDate));
        }
        if (durationMonths != null) {
          form.fields.add(MapEntry('duration_months', durationMonths.toString()));
        }
        if (fileBytes != null && fileBytes.isNotEmpty) {
          form.files.add(MapEntry('certificate', multipartFromBytes(fileBytes, fileName ?? 'certificate.pdf')));
        }
        final res = await _dio.post('/candidates/certifications', data: form);
        return asMap(res.data)['id']?.toString() ?? '';
      });

  Future<void> deleteCertification(String id) =>
      guard(() async => _dio.delete('/candidates/certifications/$id'));

  // ── RVM verification (flag-gated) ───────────────────────────────────────
  Future<RvmVerificationStatus> rvmVerification() => guard(() async =>
      Parse.rvmVerificationStatus((await _dio.get('/candidates/rvm-verification')).data));

  /// Submit an RVM training-verification request. Returns the new record's
  /// status. 404 (feature off) / 409 (already pending/approved) surface as
  /// typed failures for the UI.
  Future<String> submitRvmVerification({
    required String trainingStartDate,
    required String trainingEndDate,
    required String industry,
    required String jobDomain,
    required String jobRole,
    required List<String> skills,
    required List<int> certificateBytes,
    required String certificateName,
  }) =>
      guard(() async {
        final form = FormData();
        form.fields
          ..add(MapEntry('training_start_date', trainingStartDate))
          ..add(MapEntry('training_end_date', trainingEndDate))
          ..add(MapEntry('industry', industry))
          ..add(MapEntry('job_domain', jobDomain))
          ..add(MapEntry('job_role', jobRole))
          // Backend expects `skills` as a JSON array string.
          ..add(MapEntry('skills', jsonEncode(skills)));
        form.files.add(MapEntry('certificate', multipartFromBytes(certificateBytes, certificateName)));
        final res = await _dio.post('/candidates/rvm-verification', data: form);
        return asMap(res.data)['status']?.toString() ?? 'pending_review';
      });
}

/// A candidate-authored experience entry ready to POST/PATCH. Kept in the data
/// layer so blocs/UI never hand-build backend JSON.
class ExperienceDraft {
  const ExperienceDraft({
    required this.jobDomain,
    this.companyName,
    this.industry,
    this.jobRole,
    this.skills = const [],
    this.durationMonths,
    this.isCurrent = false,
    this.startDate,
    this.endDate,
  });

  final String jobDomain;
  final String? companyName;
  final String? industry;
  final String? jobRole;
  final List<String> skills;
  final int? durationMonths;
  final bool isCurrent;
  final DateTime? startDate;
  final DateTime? endDate;

  static String? _date(DateTime? d) => d == null ? null : d.toIso8601String().split('T').first;

  Map<String, dynamic> toJson() => {
        'job_domain': jobDomain,
        if (companyName != null) 'company_name': companyName,
        if (industry != null) 'industry': industry,
        if (jobRole != null) 'job_role': jobRole,
        'skills': skills,
        if (durationMonths != null) 'duration_months': durationMonths,
        'is_current': isCurrent,
        if (startDate != null) 'start_date': _date(startDate),
        if (endDate != null) 'end_date': _date(endDate),
      };
}
