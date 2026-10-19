/// The candidate self-registration payload for `POST /auth/registrations`
/// (sent after the phone/OTP session is established). `toJson` matches the
/// backend's sectioned shape (`personal / experience / skills / preferences /
/// profile / salary`).
///
/// The core fields are required; the expanded fields (industry, education,
/// salary, relocation) are all OPTIONAL and only emitted when provided — so
/// older callers that pass just the core set produce exactly the same payload
/// as before (backward compatible), while the full registration wizard can send
/// everything.
class CandidateRegistration {
  const CandidateRegistration({
    required this.fullName,
    required this.phone,
    required this.dateOfBirth, // YYYY-MM-DD
    required this.gender, // male | female | other | prefer_not_to_say
    required this.city,
    required this.state,
    required this.pincode, // 6 digits
    required this.jobDomain,
    required this.jobRole,
    required this.skills, // >= 1
    required this.preferredJobTypes, // >= 1 of full_time|part_time|contract|internship
    required this.preferredLocations, // >= 1, <= 5
    this.isFresher = false,
    this.locale = 'en',
    // ── Expanded (full registration form) — all optional ──
    this.industry,
    this.highestQualification,
    this.collegeName,
    this.passingYear,
    this.currentMonthlySalary,
    this.expectedMonthlySalary,
    this.openToRelocation = false,
  });

  final String fullName;
  final String phone;
  final String dateOfBirth;
  final String gender;
  final String city;
  final String state;
  final String pincode;
  final String jobDomain;
  final String jobRole;
  final List<String> skills;
  final List<String> preferredJobTypes;
  final List<String> preferredLocations;
  final bool isFresher;
  final String locale;

  final String? industry;
  final String? highestQualification;
  final String? collegeName;
  final int? passingYear;
  final num? currentMonthlySalary;
  final num? expectedMonthlySalary;
  final bool openToRelocation;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'personal': {
        'full_name': fullName,
        'phone': phone,
        'date_of_birth': dateOfBirth,
        'gender': gender,
        'city': city,
        'state': state,
        'pincode': pincode,
        'locale': locale,
      },
      'experience': {'is_fresher': isFresher},
      'skills': {
        'job_domain': jobDomain,
        'job_role': jobRole,
        'skills': skills,
        if (industry != null && industry!.isNotEmpty) 'industry': industry,
      },
      'preferences': {
        'preferred_job_types': preferredJobTypes,
        'preferred_locations': preferredLocations,
        'open_to_relocation': openToRelocation,
      },
    };

    // profile (education) — only when a qualification was provided.
    if (highestQualification != null && highestQualification!.isNotEmpty) {
      final hasCollege = collegeName != null && collegeName!.isNotEmpty;
      json['profile'] = {
        'highest_qualification': highestQualification,
        if (hasCollege) 'college_name': collegeName,
        if (passingYear != null) 'passing_year': passingYear,
        'education_details': [
          {
            'degree_type': highestQualification,
            if (hasCollege) 'institute': collegeName,
            if (passingYear != null) 'passing_year': passingYear,
          }
        ],
      };
    }

    // salary — only when provided (backend derives expected LPA from monthly).
    if (currentMonthlySalary != null || expectedMonthlySalary != null) {
      json['salary'] = {
        if (currentMonthlySalary != null) 'current_monthly_salary': currentMonthlySalary,
        if (expectedMonthlySalary != null) 'expected_monthly_salary': expectedMonthlySalary,
      };
    }

    return json;
  }
}
