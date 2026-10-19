/// The candidate's admission-intake status as the app's Learning gate sees it,
/// from `GET /api/intakes/by-phone/:phone`. Server-side truth (keyed by phone),
/// so it survives a reinstall or a new device.
library;

enum IntakePhase {
  /// No submitted intake for this phone — show the apply form.
  none,

  /// Submitted; awaiting the office's review.
  underReview,

  /// Linked to an admission — admitted.
  approved,
}

class AdmissionIntakeStatus {
  const AdmissionIntakeStatus({
    required this.exists,
    this.intakeId,
    this.status = 'draft',
    this.submitted = false,
    this.admissionId,
    this.approved = false,
    this.studentName,
    this.phone,
    this.email,
    this.dateOfBirth,
    this.dateOfJoining,
    this.fatherName,
    this.fatherPhone,
    this.identificationType,
    this.identificationNumber,
    this.currentAddress,
    this.permanentAddress,
    this.locationId,
    this.courseIds = const [],
    this.documentCount = 0,
    this.createdAt,
  });

  /// The "no intake yet" state.
  const AdmissionIntakeStatus.none() : this(exists: false);

  final bool exists;
  final String? intakeId;

  /// Raw intake status: 'draft' | 'submitted'.
  final String status;
  final bool submitted;

  /// Set once the office proceeds to admission — the approval signal.
  final String? admissionId;
  final bool approved;

  final String? studentName;
  final String? phone;
  final String? email;
  final String? dateOfBirth;
  final String? dateOfJoining;
  final String? fatherName;
  final String? fatherPhone;
  final String? identificationType;
  final String? identificationNumber;
  final String? currentAddress;
  final String? permanentAddress;

  /// Scheduler location_id (1 Faridabad, 2 Pune, 3 Ahmedabad, 4 Lucknow).
  final int? locationId;
  final List<String> courseIds;
  final int documentCount;
  final DateTime? createdAt;

  IntakePhase get phase {
    if (!exists) return IntakePhase.none;
    if (approved) return IntakePhase.approved;
    if (submitted) return IntakePhase.underReview;
    return IntakePhase.none; // draft → let them finish via the form
  }
}
