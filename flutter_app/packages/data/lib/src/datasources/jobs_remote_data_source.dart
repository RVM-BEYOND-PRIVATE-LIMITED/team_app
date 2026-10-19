import 'package:dio/dio.dart';
import 'package:domain/domain.dart';

import '../parsers.dart';
import 'dio_executor.dart';

/// Candidate job flows over the JobPortal Dio. Parses JSON → domain models.
class JobsRemoteDataSource with DioExecutor {
  JobsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<JobSummary>> browse({
    int page = 1,
    String? domain,
    String? role,
    String? location,
    num? salaryMin,
    num? salaryMax,
  }) =>
      guard(() async {
        // Backend is GET /candidates/job-listings with query params (a POST 405s).
        // It derives the candidate's domain from their profile; only these
        // filters are honoured server-side.
        final r = await _dio.get('/candidates/job-listings', queryParameters: {
          'page': page,
          if (role != null) 'job_type': role,
          if (location != null) 'search': location,
          if (salaryMin != null) 'min_salary_lpa': salaryMin,
          if (salaryMax != null) 'max_salary_lpa': salaryMax,
        });
        return Parse.jobList(r.data);
      });

  Future<JobDetail> job(String jobId) =>
      guard(() async => Parse.jobDetail(asMap((await _dio.get('/public/jobs/$jobId')).data)));

  Future<List<SavedJob>> savedJobs() =>
      guard(() async => Parse.savedJobs((await _dio.get('/candidates/saved-jobs')).data));

  /// Save a job → returns the saved-record id (used later to unsave).
  Future<String> save(String jobId) => guard(() async {
        final data = asMap((await _dio.post('/candidates/saved-jobs', data: {'job_id': jobId})).data);
        return (data['id'] ?? '').toString();
      });

  Future<void> unsave(String savedJobId) =>
      guard(() async => _dio.delete('/candidates/saved-jobs/$savedJobId'));

  /// Partial profile update (PATCH). Send only the changed fields.
  Future<void> updateProfile(Map<String, dynamic> fields) =>
      guard(() async => _dio.patch('/candidates/profile', data: fields));

  Future<void> apply(String jobId, {String? coverNote}) => guard(() async => _dio.post(
        '/candidates/applications',
        data: {'job_id': jobId, if (coverNote != null) 'cover_note': coverNote},
      ));

  Future<List<ApplicationSummary>> myApplications() =>
      guard(() async => Parse.applications((await _dio.get('/candidates/applications')).data));

  Future<ApplicationDetail> application(String id) => guard(
      () async => Parse.applicationDetail(asMap((await _dio.get('/candidates/applications/$id')).data)));

  /// Withdraw an application. Backend returns 409 if it's past the withdrawable
  /// stage — that surfaces as a [Failure] the UI can show.
  Future<void> withdrawApplication(String id) =>
      guard(() async => _dio.delete('/candidates/applications/$id'));

  Future<CandidateProfile> profile() =>
      guard(() async => Parse.candidate(asMap((await _dio.get('/candidates/profile')).data)));

  /// JobPortal announcements targeted at candidates.
  Future<List<AnnouncementItem>> candidateAnnouncements() => guard(() async => Parse.candidateAnnouncements(
      (await _dio.get('/announcements', queryParameters: {'audience': 'candidates'})).data));
}
