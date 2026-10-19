/// One entry in a candidate's work-experience stack
/// (GET/POST/PATCH/DELETE /candidates/experience-stack).
class ExperienceEntry {
  const ExperienceEntry({
    required this.id,
    required this.jobDomain,
    this.companyName,
    this.industry,
    this.jobRole,
    this.skills = const [],
    this.durationMonths,
    this.isCurrent = false,
    this.startDate,
    this.endDate,
    this.source,
    this.createdAt,
  });

  final String id;

  /// The only field the backend requires on create.
  final String jobDomain;
  final String? companyName;
  final String? industry;
  final String? jobRole;
  final List<String> skills;
  final int? durationMonths;
  final bool isCurrent;
  final DateTime? startDate;
  final DateTime? endDate;

  /// e.g. `manual_experience` or `rvm_verified_training` (read-only badge).
  final String? source;
  final DateTime? createdAt;

  /// RVM-verified training blocks are managed by the institute, not the
  /// candidate, so the UI must not offer edit/delete for them.
  bool get isReadOnly => source == 'rvm_verified_training';

  /// Headline for a list card: "Role · Company" falling back to the domain.
  String get title {
    final parts = [jobRole, companyName].whereType<String>().where((e) => e.isNotEmpty);
    return parts.isEmpty ? jobDomain : parts.join(' · ');
  }
}
