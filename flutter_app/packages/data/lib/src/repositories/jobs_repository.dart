import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/jobs_remote_data_source.dart';
import 'connectivity_guard.dart';

class JobsRepository with ConnectivityGuard {
  JobsRepository({required JobsRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final JobsRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<JobSummary>> browse({
    int page = 1,
    String? domain,
    String? role,
    String? location,
    num? salaryMin,
    num? salaryMax,
  }) async {
    await ensureOnline();
    return _remote.browse(
      page: page,
      domain: domain,
      role: role,
      location: location,
      salaryMin: salaryMin,
      salaryMax: salaryMax,
    );
  }

  Future<JobDetail> job(String jobId) async {
    await ensureOnline();
    return _remote.job(jobId);
  }

  Future<List<SavedJob>> savedJobs() async {
    await ensureOnline();
    return _remote.savedJobs();
  }

  Future<String> save(String jobId) async {
    await ensureOnline();
    return _remote.save(jobId);
  }

  Future<void> unsave(String savedJobId) async {
    await ensureOnline();
    return _remote.unsave(savedJobId);
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    await ensureOnline();
    return _remote.updateProfile(fields);
  }

  Future<void> apply(String jobId, {String? coverNote}) async {
    await ensureOnline();
    return _remote.apply(jobId, coverNote: coverNote);
  }

  Future<List<ApplicationSummary>> myApplications() async {
    await ensureOnline();
    return _remote.myApplications();
  }

  Future<ApplicationDetail> application(String id) async {
    await ensureOnline();
    return _remote.application(id);
  }

  Future<void> withdrawApplication(String id) async {
    await ensureOnline();
    return _remote.withdrawApplication(id);
  }

  Future<CandidateProfile> profile() async {
    await ensureOnline();
    return _remote.profile();
  }

  Future<List<AnnouncementItem>> candidateAnnouncements() async {
    await ensureOnline();
    return _remote.candidateAnnouncements();
  }
}
