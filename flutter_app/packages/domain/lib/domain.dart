/// Pure-Dart app models the UI/blocs consume.
///
/// Rule: UI and blocs import from here. Data sources in `data/` parse backend
/// JSON straight into these models, so a backend change is absorbed there.
library domain;

export 'src/models/auth_user.dart';
export 'src/models/staff_identity.dart';
export 'src/util/jwt.dart';
export 'src/models/batch_summary.dart';
export 'src/models/staff_batch.dart';
export 'src/models/staff_student.dart';
export 'src/models/staff_admission.dart';
export 'src/models/staff_account.dart';
export 'src/models/staff_allotment.dart';
export 'src/models/staff_followup.dart';
export 'src/models/staff_faculty.dart';
export 'src/models/staff_substitution.dart';
export 'src/models/staff_ticket.dart';
export 'src/models/staff_certificate.dart';
export 'src/models/staff_skill.dart';
export 'src/models/staff_course.dart';
export 'src/models/staff_intake.dart';
export 'src/models/staff_alert.dart';
export 'src/models/staff_activity.dart';
export 'src/models/staff_scheduling.dart';
export 'src/models/staff_user.dart';
export 'src/models/staff_ceo.dart';
export 'src/models/upload_file.dart';
export 'src/models/attendance.dart';
export 'src/models/dashboard_summary.dart';
export 'src/models/job_summary.dart';
export 'src/models/job_detail.dart';
export 'src/models/saved_job.dart';
export 'src/models/application_summary.dart';
export 'src/models/application_detail.dart';
export 'src/models/candidate_profile.dart';
export 'src/models/candidate_registration.dart';
export 'src/models/job_taxonomy.dart';
export 'src/models/experience_entry.dart';
export 'src/models/skill_suggestion.dart';
export 'src/models/certification.dart';
export 'src/models/feedback_item.dart';
export 'src/models/chat_message.dart';
export 'src/models/offer.dart';
export 'src/models/password_auth_result.dart';
export 'src/models/rvm_verification.dart';
export 'src/models/announcement_item.dart';
export 'src/models/support_ticket.dart';
export 'src/models/company.dart';
export 'src/models/admission_intake_status.dart';
export 'src/mappers/enum_parsers.dart';
