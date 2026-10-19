/// Scheduler admission-intake (new-admission enquiry + undertaking) as the staff
/// worklist sees it. A prospective student's captured details, the three
/// undertaking flags, and the submission status; staff finalize the undertaking
/// and "proceed" to prefill an admission form.
class Intake {
  const Intake({
    required this.id,
    required this.studentName,
    this.studentPhone,
    this.fatherName,
    this.fatherPhone,
    this.email,
    this.dateOfBirth,
    this.dateOfJoining,
    this.identificationType,
    this.identificationNumber,
    this.courseIds = const [],
    this.feeAmount,
    this.currentAddress,
    this.permanentAddress,
    this.videoCompleted = false,
    this.contactsAcknowledged = false,
    this.termsAccepted = false,
    this.status = 'draft',
    this.admissionId,
    this.identificationFileCount = 0,
    this.createdAt,
  });

  final String id;
  final String studentName;
  final String? studentPhone;
  final String? fatherName;
  final String? fatherPhone;
  final String? email;
  final DateTime? dateOfBirth;
  final DateTime? dateOfJoining;
  final String? identificationType;
  final String? identificationNumber;
  final List<String> courseIds;
  final num? feeAmount;
  final String? currentAddress;
  final String? permanentAddress;
  final bool videoCompleted;
  final bool contactsAcknowledged;
  final bool termsAccepted;
  final String status; // draft | submitted
  final String? admissionId;
  final int identificationFileCount;
  final DateTime? createdAt;

  bool get isSubmitted => status == 'submitted';
  bool get undertakingComplete => videoCompleted && contactsAcknowledged && termsAccepted;
}

/// GET /intake/:id/proceed → the prefill subset for handing off to an admission
/// form (read-only preview in mobile until admission-create lands).
class IntakePrefill {
  const IntakePrefill({
    this.locationId,
    this.studentName,
    this.studentPhone,
    this.fatherName,
    this.fatherPhone,
    this.identificationType,
    this.identificationNumber,
    this.courseIds = const [],
    this.courseStartDate,
    this.currentAddress,
    this.permanentAddress,
  });

  final int? locationId;
  final String? studentName;
  final String? studentPhone;
  final String? fatherName;
  final String? fatherPhone;
  final String? identificationType;
  final String? identificationNumber;
  final List<String> courseIds;
  final DateTime? courseStartDate;
  final String? currentAddress;
  final String? permanentAddress;
}

/// POST /intake create payload (the public enquiry body). Wired at the data
/// layer; the mobile compose form is deferred (many fields + course picker +
/// the separate multipart ID-file upload).
class IntakeDraft {
  const IntakeDraft({
    required this.studentPhoneNumber,
    this.locationId,
    this.studentName,
    this.fatherName,
    this.fatherPhoneNumber,
    this.email,
    this.dateOfBirth,
    this.dateOfJoining,
    this.identificationType,
    this.identificationNumber,
    this.courseIds = const [],
    this.feeAmount,
    this.currentAddress,
    this.permanentAddress,
  });

  final String studentPhoneNumber;
  final int? locationId;
  final String? studentName;
  final String? fatherName;
  final String? fatherPhoneNumber;
  final String? email;
  final String? dateOfBirth;
  final String? dateOfJoining;
  final String? identificationType;
  final String? identificationNumber;
  final List<String> courseIds;
  final num? feeAmount;
  final String? currentAddress;
  final String? permanentAddress;

  Map<String, dynamic> toJson() => {
        'student_phone_number': studentPhoneNumber,
        if (locationId != null) 'location_id': locationId,
        if (studentName != null) 'student_name': studentName,
        if (fatherName != null) 'father_name': fatherName,
        if (fatherPhoneNumber != null) 'father_phone_number': fatherPhoneNumber,
        if (email != null) 'email': email,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (dateOfJoining != null) 'date_of_joining': dateOfJoining,
        if (identificationType != null) 'identification_type': identificationType,
        if (identificationNumber != null) 'identification_number': identificationNumber,
        'course_ids': courseIds,
        if (feeAmount != null) 'fee_amount': feeAmount,
        if (currentAddress != null) 'current_address': currentAddress,
        if (permanentAddress != null) 'permanent_address': permanentAddress,
      };
}
