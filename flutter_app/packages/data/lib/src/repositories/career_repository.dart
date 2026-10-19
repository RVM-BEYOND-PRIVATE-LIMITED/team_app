import 'package:core_network/core_network.dart';
import 'package:domain/domain.dart';

import '../datasources/career_remote_data_source.dart';
import 'connectivity_guard.dart';

/// Candidate career profile: work-experience stack + skill autocomplete.
class CareerRepository with ConnectivityGuard {
  CareerRepository({required CareerRemoteDataSource remote, required this.connectivity})
      : _remote = remote;

  final CareerRemoteDataSource _remote;

  @override
  final ConnectivityService connectivity;

  Future<List<ExperienceEntry>> experienceStack() async {
    await ensureOnline();
    return _remote.experienceStack();
  }

  Future<ExperienceEntry> addExperience(ExperienceDraft draft) async {
    await ensureOnline();
    return _remote.addExperience(draft);
  }

  Future<ExperienceEntry> updateExperience(String id, ExperienceDraft draft) async {
    await ensureOnline();
    return _remote.updateExperience(id, draft);
  }

  Future<void> deleteExperience(String id) async {
    await ensureOnline();
    return _remote.deleteExperience(id);
  }

  Future<List<SkillSuggestion>> skillSuggestions(String query, {String? category}) async {
    await ensureOnline();
    return _remote.skillSuggestions(query, category: category);
  }

  // ── Resume / avatar ───────────────────────────────────────────────────────
  Future<String> uploadResume(List<int> bytes, String filename) async {
    await ensureOnline();
    return _remote.uploadResume(bytes, filename);
  }

  Future<void> deleteResume() async {
    await ensureOnline();
    return _remote.deleteResume();
  }

  Future<String> uploadAvatar(List<int> bytes, String filename) async {
    await ensureOnline();
    return _remote.uploadAvatar(bytes, filename);
  }

  Future<void> deleteAvatar() async {
    await ensureOnline();
    return _remote.deleteAvatar();
  }

  /// Avatar image bytes via the backend proxy, or null when there's no photo.
  /// Intentionally does NOT call [ensureOnline] (which throws when offline) —
  /// the caller renders a silent fallback, so this stays throw-free for the
  /// common paths and never trips a "paused on exception".
  Future<List<int>?> avatarImage() => _remote.avatarImage();

  // ── Certifications ────────────────────────────────────────────────────────
  Future<List<Certification>> certifications() async {
    await ensureOnline();
    return _remote.certifications();
  }

  Future<String> addCertification({
    required String name,
    String? issuingAuthority,
    String? issueDate,
    int? durationMonths,
    List<int>? fileBytes,
    String? fileName,
  }) async {
    await ensureOnline();
    return _remote.addCertification(
      name: name,
      issuingAuthority: issuingAuthority,
      issueDate: issueDate,
      durationMonths: durationMonths,
      fileBytes: fileBytes,
      fileName: fileName,
    );
  }

  Future<void> deleteCertification(String id) async {
    await ensureOnline();
    return _remote.deleteCertification(id);
  }

  // ── RVM verification ──────────────────────────────────────────────────────
  Future<RvmVerificationStatus> rvmVerification() async {
    await ensureOnline();
    return _remote.rvmVerification();
  }

  Future<String> submitRvmVerification({
    required String trainingStartDate,
    required String trainingEndDate,
    required String industry,
    required String jobDomain,
    required String jobRole,
    required List<String> skills,
    required List<int> certificateBytes,
    required String certificateName,
  }) async {
    await ensureOnline();
    return _remote.submitRvmVerification(
      trainingStartDate: trainingStartDate,
      trainingEndDate: trainingEndDate,
      industry: industry,
      jobDomain: jobDomain,
      jobRole: jobRole,
      skills: skills,
      certificateBytes: certificateBytes,
      certificateName: certificateName,
    );
  }
}
