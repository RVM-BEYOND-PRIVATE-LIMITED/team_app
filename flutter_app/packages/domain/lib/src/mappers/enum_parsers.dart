import '../models/auth_user.dart';
import '../models/batch_summary.dart';
import '../models/job_summary.dart';
import '../models/application_summary.dart';
import '../models/feedback_item.dart';
import '../models/support_ticket.dart';

/// String -> domain enum, tolerant of unknown backend values (never throws).
/// Both backends send enums as snake/space/Title strings; normalise here.

AppRole parseAppRole(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'admin':
      return AppRole.admin;
    case 'faculty':
      return AppRole.faculty;
    case 'super_admin':
      return AppRole.superAdmin;
    // DB enum uses `accounts`; middleware/contract use `accounts_admin`.
    case 'accounts_admin':
    case 'accounts':
      return AppRole.accountsAdmin;
    case 'ceo':
      return AppRole.ceo;
    case 'hoo':
      return AppRole.hoo;
    case 'hod':
      return AppRole.hod;
    case 'admin_manager':
      return AppRole.adminManager;
    case 'hr':
      return AppRole.hr;
    case 'hr_executive':
      return AppRole.hrExecutive;
    case 'hod_placement':
      return AppRole.hodPlacement;
    case 'admin_executive':
      return AppRole.adminExecutive;
    case 'placement_head':
      return AppRole.placementHead;
    case 'placement_executive':
      return AppRole.placementExecutive;
    case 'student':
      return AppRole.student;
    case 'candidate':
      return AppRole.candidate;
    case 'company':
      return AppRole.company;
    default:
      return AppRole.unknown;
  }
}

/// domain AppRole -> a human name for the UI (never the raw role id).
String appRoleLabel(AppRole role) => switch (role) {
      AppRole.admin => 'Admin',
      AppRole.faculty => 'Faculty',
      AppRole.superAdmin => 'Super Admin',
      AppRole.accountsAdmin => 'Accounts Admin',
      AppRole.ceo => 'CEO',
      AppRole.hoo => 'Head of Operations',
      AppRole.hod => 'Head of Department',
      AppRole.adminManager => 'Admin Manager',
      AppRole.hr => 'HR',
      AppRole.hrExecutive => 'HR Executive',
      AppRole.hodPlacement => 'Head of Department (Placement)',
      AppRole.adminExecutive => 'Admin Executive',
      AppRole.placementHead => 'Placement Head',
      AppRole.placementExecutive => 'Placement Executive',
      AppRole.student => 'Student',
      AppRole.candidate => 'Candidate',
      AppRole.company => 'Company',
      AppRole.unknown => 'Member',
    };

/// A wire role string (`super_admin`) as its human name (`Super Admin`).
String appRoleLabelFromWire(String? role) => appRoleLabel(parseAppRole(role));

/// domain AppRole -> the wire string the Scheduler backend uses.
String? appRoleWire(AppRole role) => switch (role) {
      AppRole.admin => 'admin',
      AppRole.faculty => 'faculty',
      AppRole.superAdmin => 'super_admin',
      AppRole.accountsAdmin => 'accounts_admin',
      AppRole.ceo => 'ceo',
      AppRole.hoo => 'hoo',
      AppRole.hod => 'hod',
      AppRole.adminManager => 'admin_manager',
      AppRole.hr => 'hr',
      AppRole.hrExecutive => 'hr_executive',
      AppRole.hodPlacement => 'hod_placement',
      AppRole.adminExecutive => 'admin_executive',
      AppRole.placementHead => 'placement_head',
      AppRole.placementExecutive => 'placement_executive',
      AppRole.student => 'student',
      AppRole.candidate => 'candidate',
      AppRole.company => 'company',
      AppRole.unknown => null,
    };

BatchStatus parseBatchStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'upcoming':
      return BatchStatus.upcoming;
    case 'active':
      return BatchStatus.active;
    case 'completed':
      return BatchStatus.completed;
    default:
      return BatchStatus.unknown;
  }
}

JobType parseJobType(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'full_time':
      return JobType.fullTime;
    case 'part_time':
      return JobType.partTime;
    case 'contract':
      return JobType.contract;
    case 'internship':
      return JobType.internship;
    default:
      return JobType.unknown;
  }
}

TicketStatus parseTicketStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'open':
      return TicketStatus.open;
    case 'replied':
    case 'in progress':
    case 'in_progress':
      return TicketStatus.replied;
    case 'resolved':
      return TicketStatus.resolved;
    case 'closed':
      return TicketStatus.closed;
    default:
      return TicketStatus.unknown;
  }
}

FeedbackType parseFeedbackType(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'bug':
      return FeedbackType.bug;
    case 'suggestion':
      return FeedbackType.suggestion;
    case 'complaint':
      return FeedbackType.complaint;
    case 'feature_request':
      return FeedbackType.featureRequest;
    case 'job_issue':
      return FeedbackType.jobIssue;
    case 'account_issue':
      return FeedbackType.accountIssue;
    default:
      return FeedbackType.other;
  }
}

/// domain FeedbackType -> the wire string the JobPortal backend expects.
String feedbackTypeWire(FeedbackType t) => switch (t) {
      FeedbackType.bug => 'bug',
      FeedbackType.suggestion => 'suggestion',
      FeedbackType.complaint => 'complaint',
      FeedbackType.featureRequest => 'feature_request',
      FeedbackType.jobIssue => 'job_issue',
      FeedbackType.accountIssue => 'account_issue',
      FeedbackType.other => 'other',
    };

ApplicationStatus parseApplicationStatus(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'pending':
      return ApplicationStatus.pending;
    case 'under_review':
      return ApplicationStatus.underReview;
    case 'shortlisted':
      return ApplicationStatus.shortlisted;
    case 'interview_scheduled':
      return ApplicationStatus.interviewScheduled;
    case 'offer_made':
      return ApplicationStatus.offerMade;
    case 'hired':
      return ApplicationStatus.hired;
    case 'rejected':
      return ApplicationStatus.rejected;
    case 'withdrawn':
      return ApplicationStatus.withdrawn;
    default:
      return ApplicationStatus.unknown;
  }
}
