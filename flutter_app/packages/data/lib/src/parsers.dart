import 'package:domain/domain.dart';

/// JSON (Map/List from dio) → `domain` models. Kept in the data layer so a
/// backend shape change is absorbed here, not in blocs/UI.
abstract final class Parse {
  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.map(_map).toList() : const [];

  static List<String> _strings(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  static num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
  static int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
  static bool _bool(dynamic v) => v == true || v == 'true';
  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
  static String? _str(dynamic v) => v?.toString();

  // ── Jobs ──────────────────────────────────────────────────────────────
  static JobSummary jobSummary(Map<String, dynamic> j) {
    final company = _map(j['company']);
    return JobSummary(
      id: j['id'].toString(),
      title: _str(j['title']) ?? '',
      jobType: parseJobType(_str(j['job_type'])),
      companyId: _str(j['company_id']),
      companyName: _str(company['name']),
      location: _str(j['location']),
      salaryMinLpa: _num(j['salary_min_lpa']),
      salaryMaxLpa: _num(j['salary_max_lpa']),
      requiredSkills: _strings(j['required_skills']),
      requiredDomain: _str(j['required_domain']),
      openings: _int(j['openings']),
      applicationDeadline: _date(j['application_deadline']),
      postedAt: _date(j['created_at']),
    );
  }

  static List<JobSummary> jobList(dynamic data) {
    // browse returns { jobs:[...] }; some list endpoints return a bare [...].
    final list = data is Map ? data['jobs'] : data;
    return _list(list).map(jobSummary).toList();
  }

  /// Saved jobs: `{ saved_jobs: [{ id, saved_at, job:{...} }] }`. Each carries
  /// the saved-record id (needed to unsave) + the nested job.
  static List<SavedJob> savedJobs(dynamic data) {
    final list = data is Map ? (data['saved_jobs'] ?? data['jobs']) : data;
    return _list(list)
        .map((s) => SavedJob(savedId: s['id'].toString(), job: jobSummary(_map(s['job']))))
        .toList();
  }

  static JobDetail jobDetail(Map<String, dynamic> j) {
    final company = _map(j['company']);
    final verified = (_str(company['approval_status']) ?? '').toLowerCase().contains('approved');
    final subtitleParts = <String>[
      if (_str(company['industry'])?.isNotEmpty ?? false) _str(company['industry'])!,
      if (_str(company['size'])?.isNotEmpty ?? false) '${company['size']} staff',
      if (verified) 'Verified',
    ];
    return JobDetail(
      id: j['id'].toString(),
      title: _str(j['title']) ?? '',
      jobType: parseJobType(_str(j['job_type'])),
      companyId: _str(j['company_id']),
      companyName: _str(company['name']),
      companyVerified: verified,
      companySubtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' · '),
      location: _str(j['location']),
      salaryMinLpa: _num(j['salary_min_lpa']),
      salaryMaxLpa: _num(j['salary_max_lpa']),
      requiredSkills: _strings(j['required_skills']),
      requiredDomain: _str(j['required_domain']),
      requiredRole: _str(j['required_role']),
      openings: _int(j['openings']),
      experienceMinMonths: _int(j['experience_min_months']),
      experienceMaxMonths: _int(j['experience_max_months']),
      description: _str(j['description']),
      applicationDeadline: _date(j['application_deadline']),
    );
  }

  // ── Applications ──────────────────────────────────────────────────────
  // List nests the job under `job_postings`; the detail endpoint under `job`.
  static ApplicationSummary application(Map<String, dynamic> a) {
    final job = _map(a['job'] ?? a['job_postings']);
    final company = _map(job['company']);
    return ApplicationSummary(
      id: a['id'].toString(),
      jobId: _str(a['job_id']) ?? _str(job['id']) ?? '',
      status: parseApplicationStatus(_str(a['status'])),
      jobTitle: _str(job['title']),
      companyName: _str(company['name']),
      appliedAt: _date(a['created_at']),
    );
  }

  static List<ApplicationSummary> applications(dynamic data) =>
      _list(data).map(application).toList();

  static ApplicationDetail applicationDetail(Map<String, dynamic> a) {
    final job = _map(a['job'] ?? a['job_postings']);
    final company = _map(job['company']);
    return ApplicationDetail(
      id: a['id'].toString(),
      status: parseApplicationStatus(_str(a['status'])),
      jobId: _str(a['job_id']) ?? _str(job['id']) ?? '',
      jobTitle: _str(job['title']),
      companyName: _str(company['name']),
      location: _str(job['location']) ?? _str(company['city']),
      salaryMinLpa: _num(job['salary_min_lpa']),
      salaryMaxLpa: _num(job['salary_max_lpa']),
      coverNote: _str(a['cover_note']),
      appliedAt: _date(a['created_at']),
      updatedAt: _date(a['updated_at']),
    );
  }

  // ── Candidate ─────────────────────────────────────────────────────────
  static CandidateProfile candidate(Map<String, dynamic> c) => CandidateProfile(
        id: c['id'].toString(),
        fullName: _str(c['full_name']),
        phone: _str(c['phone']),
        city: _str(c['city']),
        state: _str(c['state']),
        // The avatar bucket is private: the backend returns a short-lived signed
        // URL (`avatar_signed_url`) for display; `avatar_url` is only the raw
        // storage path (not directly loadable). Prefer the signed URL.
        avatarUrl: _str(c['avatar_signed_url']) ?? _str(c['avatar_url']),
        resumeUrl: _str(c['resume_url']),
        skills: {..._strings(c['skills']), ..._strings(c['cad_software'])}.toList(),
        profileCompletionPct: _int(c['profile_completion_pct']),
        jobDomain: _str(c['job_domain']),
        jobRole: _str(c['job_role']),
        expectedSalaryMinLpa: _num(c['expected_salary_min_lpa']),
        expectedSalaryMaxLpa: _num(c['expected_salary_max_lpa']),
        preferredLocations: _strings(c['preferred_locations']),
        isPremium: _bool(c['is_premium']),
      );

  // ── Password auth (login / reset-set / setup-set) ───────────────────────
  static PasswordAuthResult passwordAuthResult(Map<String, dynamic> m) {
    final redirect = _str(m['redirectTo'] ?? m['redirect']);
    // /login signals a ban via `banned:true`; reset/setup `set` instead return
    // redirectTo `/candidate/banned` with no banned flag — treat both as banned
    // so a banned candidate is never silently signed in.
    final banned = _bool(m['banned']) || (redirect?.contains('/banned') ?? false);
    return PasswordAuthResult(
      userId: _str(m['user_id']),
      role: _str(m['role']),
      redirectTo: redirect,
      banned: banned,
      banType: _str(m['ban_type']),
    );
  }

  // ── Auth ──────────────────────────────────────────────────────────────
  static AuthUser authUser(Map<String, dynamic> m) => AuthUser(
        id: (m['user_id'] ?? m['id']).toString(),
        role: parseAppRole(_str(m['role'])),
      );

  // ── Announcements ─────────────────────────────────────────────────────
  static AnnouncementItem announcement(Map<String, dynamic> a) => AnnouncementItem(
        id: a['id'].toString(),
        title: _str(a['title']) ?? '',
        category: switch ((_str(a['scope']) ?? '').toLowerCase()) {
          'batch' => AnnouncementCategory.batch,
          'all' => AnnouncementCategory.institute,
          _ => AnnouncementCategory.unknown,
        },
        body: _str(a['message']),
        batchId: _str(a['batch_id']),
        batchName: a['batch'] is Map ? _str(_map(a['batch'])['name']) : null,
        createdAt: _date(a['created_at']),
      );

  static List<AnnouncementItem> announcements(dynamic data) =>
      _list(data).map(announcement).toList();

  static AnnouncementItem announcementOf(dynamic data) => announcement(_map(data));

  // ── Certificates ─────────────────────────────────────────────────────────
  static Certificate certificate(Map<String, dynamic> c) => Certificate(
        id: (c['id']).toString(),
        name: _str(c['name']) ?? '',
        cost: _num(c['cost']),
      );

  static List<Certificate> certificates(dynamic data) => _list(data).map(certificate).toList();

  /// Handles GET /:id (bare row) and POST/PUT (`{certificate:{...}}` wrapper).
  static Certificate certificateOf(dynamic data) {
    final m = _map(data);
    return certificate(m['certificate'] is Map ? _map(m['certificate']) : m);
  }

  // ── Skills ───────────────────────────────────────────────────────────────
  static Skill skill(Map<String, dynamic> s) => Skill(
        id: (s['id']).toString(),
        name: _str(s['name']) ?? '',
        category: _str(s['category']),
        description: _str(s['description']),
        locationId: _int(s['location_id']),
      );

  static List<Skill> skills(dynamic data) => _list(data).map(skill).toList();

  /// POST/PUT /skills return the bare created/updated row.
  static Skill skillOf(dynamic data) => skill(_map(data));

  // ── Courses ──────────────────────────────────────────────────────────────
  /// GET /courses item → `{...course, book_count, price_formatted}`.
  static Course course(Map<String, dynamic> c) => Course(
        id: (c['id']).toString(),
        name: _str(c['name']) ?? '',
        price: _num(c['price']),
        priceFormatted: _str(c['price_formatted']),
        bookCount: _int(c['book_count']) ?? 0,
        books: _list(c['books']).map(courseBook).toList(),
      );

  static CourseBook courseBook(Map<String, dynamic> b) => CourseBook(
        id: (b['id']).toString(),
        title: _str(b['title'] ?? b['name']) ?? '',
        price: _num(b['price']),
      );

  static List<Course> courses(dynamic data) => _list(data).map(course).toList();

  /// GET /courses/:id → `{...course, books:[...], price_formatted}`.
  static Course courseOf(dynamic data) => course(_map(data));

  // ── Admission intakes ────────────────────────────────────────────────────
  static Intake intake(Map<String, dynamic> i) => Intake(
        id: (i['id']).toString(),
        studentName: _str(i['student_name']) ?? '—',
        studentPhone: _str(i['student_phone_number']),
        fatherName: _str(i['father_name']),
        fatherPhone: _str(i['father_phone_number']),
        email: _str(i['email']),
        dateOfBirth: _date(i['date_of_birth']),
        dateOfJoining: _date(i['date_of_joining']),
        identificationType: _str(i['identification_type']),
        identificationNumber: _str(i['identification_number']),
        courseIds: _strings(i['course_ids']),
        feeAmount: _num(i['fee_amount']),
        currentAddress: _str(i['current_address']),
        permanentAddress: _str(i['permanent_address']),
        videoCompleted: _bool(i['video_completed']),
        contactsAcknowledged: _bool(i['contacts_acknowledged']),
        termsAccepted: _bool(i['terms_accepted']),
        status: _str(i['status']) ?? 'draft',
        admissionId: _str(i['admission_id']),
        identificationFileCount: i['identification_files'] is List ? (i['identification_files'] as List).length : 0,
        createdAt: _date(i['created_at']),
      );

  static List<Intake> intakes(dynamic data) => _list(data).map(intake).toList();

  /// GET /intake/:id/proceed → `{prefill:{...}}`.
  static IntakePrefill intakePrefill(dynamic data) {
    final p = _map(_map(data)['prefill']);
    return IntakePrefill(
      locationId: _int(p['location_id']),
      studentName: _str(p['student_name']),
      studentPhone: _str(p['student_phone_number']),
      fatherName: _str(p['father_name']),
      fatherPhone: _str(p['father_phone_number']),
      identificationType: _str(p['identification_type']),
      identificationNumber: _str(p['identification_number']),
      courseIds: _strings(p['course_ids']),
      courseStartDate: _date(p['course_start_date']),
      currentAddress: _str(p['current_address']),
      permanentAddress: _str(p['permanent_address']),
    );
  }

  /// POST /intake → `{intake_id, reused}`.
  static (String id, bool reused) intakeCreateResult(dynamic data) {
    final m = _map(data);
    return ((m['intake_id']).toString(), _bool(m['reused']));
  }

  /// GET /intakes/by-phone/:phone → the candidate's own intake status + details
  /// (or `{exists:false}`). Server-side truth for the app's admission gate.
  static AdmissionIntakeStatus admissionIntakeStatus(dynamic data) {
    final m = _map(data);
    if (m['exists'] != true) return const AdmissionIntakeStatus.none();
    return AdmissionIntakeStatus(
      exists: true,
      intakeId: _str(m['intake_id']),
      status: _str(m['status']) ?? 'draft',
      submitted: _bool(m['submitted']),
      admissionId: _str(m['admission_id']),
      approved: _bool(m['approved']),
      studentName: _str(m['student_name']),
      phone: _str(m['student_phone_number']),
      email: _str(m['email']),
      dateOfBirth: _str(m['date_of_birth']),
      dateOfJoining: _str(m['date_of_joining']),
      fatherName: _str(m['father_name']),
      fatherPhone: _str(m['father_phone_number']),
      identificationType: _str(m['identification_type']),
      identificationNumber: _str(m['identification_number']),
      currentAddress: _str(m['current_address']),
      permanentAddress: _str(m['permanent_address']),
      locationId: _int(m['location_id']),
      courseIds: _strings(m['course_ids']),
      documentCount: _int(m['document_count']) ?? 0,
      createdAt: _date(m['created_at']),
    );
  }

  // ── Alerts ───────────────────────────────────────────────────────────────
  static PendingAlert pendingAlert(Map<String, dynamic> a) {
    final student = _map(a['student']);
    final batch = _map(a['batch']);
    return PendingAlert(
      id: (a['id']).toString(),
      alertType: _str(a['alert_type']),
      date: _date(a['date']),
      dateRaw: _str(a['date']),
      batchId: _str(a['batch_id']),
      studentId: _str(a['student_id']),
      studentName: _str(student['name']),
      admissionNumber: _str(student['admission_number']),
      batchName: _str(batch['name']),
      escalated: _bool(a['escalated']),
      createdAt: _date(a['created_at']),
    );
  }

  /// GET /alerts/pending → `{total_pending, alerts:[...], grouped}`.
  static List<PendingAlert> pendingAlerts(dynamic data) =>
      _list(_map(data)['alerts']).map(pendingAlert).toList();

  // ── Activities ───────────────────────────────────────────────────────────
  /// GET /activities → `[{action, item, type, created_at}]`.
  static List<Activity> activities(dynamic data) => _list(data)
      .map((a) => Activity(
            action: _str(a['action']),
            item: _str(a['item']),
            type: _str(a['type']),
            createdAt: _date(a['created_at']),
          ))
      .toList();

  // ── Scheduling ───────────────────────────────────────────────────────────
  /// GET /free-slots → `[{faculty:{id,name}, slots:[{date, time:[...]}]}]`.
  static List<FacultyFreeSlots> freeSlots(dynamic data) => _list(data)
      .map((f) => FacultyFreeSlots(
            faculty: _namedRef(f['faculty']) ?? const NamedRef(id: '', name: '—'),
            days: _list(f['slots'])
                .map((s) => FreeSlotDay(date: _str(s['date']) ?? '', times: _strings(s['time'])))
                .toList(),
          ))
      .toList();

  // ── Users ────────────────────────────────────────────────────────────────
  static StaffUser staffUser(Map<String, dynamic> u) => StaffUser(
        id: (u['id']).toString(),
        username: _str(u['username']) ?? '—',
        phoneNumber: _str(u['phone_number']),
        role: _str(u['role']),
        locationId: _int(u['location_id']),
        createdAt: _date(u['created_at']),
      );

  static List<StaffUser> staffUsers(dynamic data) => _list(data).map(staffUser).toList();

  /// POST /users/super-provision → the created user row. PATCH /users/update/:id
  /// → `{message, user:{...}}`.
  static StaffUser staffUserOf(dynamic data) {
    final m = _map(data);
    return staffUser(m['user'] is Map ? _map(m['user']) : m);
  }

  /// POST /suggestions/suggest-faculty → `{suggestions:[{id,name,commonSlots:
  /// [{start,end}], status}]}`.
  static List<FacultySuggestion> facultySuggestions(dynamic data) =>
      _list(_map(data)['suggestions'])
          .map((s) => FacultySuggestion(
                id: (s['id']).toString(),
                name: _str(s['name']) ?? '—',
                status: _str(s['status']) ?? 'available',
                commonSlots: _list(s['commonSlots'])
                    .map((c) => TimeRange(start: _str(c['start']) ?? '', end: _str(c['end']) ?? ''))
                    .toList(),
              ))
          .toList();

  // ── Batches ───────────────────────────────────────────────────────────
  static BatchSummary batch(Map<String, dynamic> b) => BatchSummary(
        id: b['id'].toString(),
        name: _str(b['name']) ?? '',
        status: parseBatchStatus(_str(b['status'])),
        facultyName: _str(b['faculty_name']),
        skillName: _str(b['skill_name']),
        startDate: _date(b['start_date']),
        endDate: _date(b['end_date']),
        startTime: _str(b['start_time']),
        endTime: _str(b['end_time']),
        joinedCount: _int(b['joined_count']),
        maxStudents: _int(b['max_students']),
      );

  static List<BatchSummary> batches(dynamic data) => _list(data).map(batch).toList();

  // ── Staff batches ─────────────────────────────────────────────────────────
  /// GET /batches → rows spreading the `batches` columns + nested
  /// `faculty`/`skill` objects, computed `status`, `students` (enrolled count),
  /// `joined_count`, and substitution flags.
  static StaffBatch staffBatch(Map<String, dynamic> b) {
    final faculty = _map(b['faculty']);
    final skill = _map(b['skill']);
    final original = _map(b['original_faculty']);
    return StaffBatch(
      id: b['id'].toString(),
      name: _str(b['name']) ?? '',
      status: parseBatchStatus(_str(b['status'])),
      description: _str(b['description']),
      facultyId: _str(b['faculty_id']),
      facultyName: _str(faculty['name']),
      skillId: _str(b['skill_id']),
      skillName: _str(skill['name']),
      startDate: _date(b['start_date']),
      endDate: _date(b['end_date']),
      startTime: _str(b['start_time']),
      endTime: _str(b['end_time']),
      maxStudents: _int(b['max_students']),
      // GET /batches returns `students` as a count int; POST/PUT return it as an
      // array of student objects — tolerate both.
      enrolledCount: b['students'] is List ? (b['students'] as List).length : _int(b['students']),
      joinedCount: _int(b['joined_count']),
      isSubstituted: _bool(b['isSubstituted']),
      originalFacultyName: _str(original['name']),
      scheduleDayNames: b['days_of_week'] is List
          ? (b['days_of_week'] as List).map((d) => d.toString()).toList()
          : const [],
    );
  }

  static List<StaffBatch> staffBatches(dynamic data) => _list(data).map(staffBatch).toList();

  /// GET /students/:id/batches → `{ batches:[...] }` (raw batch rows + nested
  /// faculty, no computed status/counts).
  static List<StaffBatch> studentBatchList(dynamic data) =>
      staffBatches(data is Map ? data['batches'] : data);

  /// GET /batches/:id/students → student roster with dues + risk flags.
  static List<BatchStudent> batchStudents(dynamic data) => _list(data)
      .map((s) => BatchStudent(
            id: s['id'].toString(),
            name: _str(s['name']) ?? '—',
            admissionNumber: _str(s['admission_number']),
            phoneNumber: _str(s['phone_number']),
            enrolledCourses: _str(s['enrolled_courses']),
            activeBatchesCount: _int(s['active_batches_count']),
            remarks: _str(s['remarks']),
            totalDue: _num(s['total_due_amount']),
            isDefaulter: _bool(s['is_defaulter']),
            isBanned: _bool(s['is_banned']),
            isSuspended: _bool(s['is_suspended']),
            isOnHold: _bool(s['is_on_hold']),
            suspendedUntil: _date(s['suspended_until']),
            nextFollowUp: _date(s['next_follow_up']),
            statusLabel: _str(s['status_label']),
          ))
      .toList();

  /// GET /batches/active-students-count → `{total_active_students,
  /// active_batches_count}`.
  static ActiveStudentsCount activeStudentsCount(dynamic data) {
    final m = _map(data);
    return ActiveStudentsCount(
      totalActiveStudents: _int(m['total_active_students']) ?? 0,
      activeBatchesCount: _int(m['active_batches_count']) ?? 0,
    );
  }

  // ── Staff students ──────────────────────────────────────────────────────
  /// A `students` row enriched by the controller with the follow-up view.
  static StaffStudent staffStudent(Map<String, dynamic> s) => StaffStudent(
        id: s['id'].toString(),
        name: _str(s['name']) ?? '—',
        admissionNumber: _str(s['admission_number']),
        phoneNumber: _str(s['phone_number']),
        remarks: _str(s['remarks']),
        locationId: _int(s['location_id']),
        totalDue: _num(s['total_due_amount']),
        isOnHold: _bool(s['is_on_hold']),
        holdCategory: _str(s['hold_category']),
        holdRemarks: _str(s['hold_remarks']),
        isDefaulter: _bool(s['is_defaulter']),
        defaulterReason: _str(s['defaulter_reason']),
        isBanned: _bool(s['is_banned']),
        isSuspended: _bool(s['is_suspended']),
        suspendedUntil: _date(s['suspended_until']),
        nextTaskDueDate: _date(_map(s['follow_up'])['next_task_due_date']),
        hasFollowupData: _bool(s['has_followup_data']),
      );

  /// GET /students → `{students:[...], count}`. Write endpoints return a bare
  /// student row — [staffStudentOf] unwraps either.
  static StudentsPage studentsPage(dynamic data) {
    final m = _map(data);
    final list = _list(m['students']).map(staffStudent).toList();
    return StudentsPage(students: list, count: _int(m['count']) ?? list.length);
  }

  static StaffStudent staffStudentOf(dynamic data) => staffStudent(_map(data));

  /// GET /students/:id/defaulter → `{is_defaulter, reason, has_admission_no}`.
  static DefaulterStatus defaulterStatus(dynamic data) {
    final m = _map(data);
    return DefaulterStatus(
      isDefaulter: _bool(m['is_defaulter']),
      reason: _str(m['reason']),
      hasAdmissionNo: _bool(m['has_admission_no']),
    );
  }

  // ── Staff admissions ────────────────────────────────────────────────────
  /// One enriched admission row (list + dropout registry). The list view keys
  /// on `admission_id`; the detail table keys on `id` — accept either.
  static AdmissionRow admissionRow(Map<String, dynamic> r) => AdmissionRow(
        id: (r['id'] ?? r['admission_id']).toString(),
        studentName: _str(r['student_name']) ?? '—',
        admissionNumber: _str(r['admission_number']),
        phoneNumber: _str(r['student_phone_number']),
        status: _str(r['status']),
        undertakingStatus: _str(r['undertaking_status']),
        approvalStatus: _str(r['approval_status']),
        totalPaid: _num(r['total_paid']),
        totalFees: _num(r['total_fees'] ?? r['total_payable_amount']),
        effectiveRemaining: _num(r['effective_remaining_due'] ?? r['balance_due']),
        createdAt: _date(r['created_at']),
        nextTaskDueDate: _date(r['next_task_due_date']),
        isDropout: _bool(r['is_dropout']),
        dropoutReason: _str(r['dropout_reason']),
        dropoutAt: _date(r['dropout_at']),
      );

  static AdmissionMetrics admissionMetrics(dynamic data) {
    final m = _map(data);
    return AdmissionMetrics(
      totalAdmissions: _int(m['totalAdmissions']) ?? 0,
      admissionsThisMonth: _int(m['admissionsThisMonth']) ?? 0,
      totalCollected: _num(m['totalCollected']) ?? 0,
      revenueCollectedThisMonth: _num(m['revenueCollectedThisMonth']) ?? 0,
      totalOutstanding: _num(m['totalOutstanding']) ?? 0,
      overdueCount: _int(m['overdueCount']) ?? 0,
    );
  }

  /// GET /admissions → `{metrics:{...}, admissions:[...]}`.
  static AdmissionsPage admissionsPage(dynamic data) {
    final m = _map(data);
    return AdmissionsPage(
      metrics: admissionMetrics(m['metrics']),
      admissions: _list(m['admissions']).map(admissionRow).toList(),
    );
  }

  /// GET /admissions/dropout-registry → `{success, admissions:[...]}`.
  static List<AdmissionRow> dropoutRegistry(dynamic data) =>
      _list(data is Map ? data['admissions'] : data).map(admissionRow).toList();

  /// GET /admissions/:id → `{...admission, courses:[...], installments:[...]}`.
  static AdmissionDetail admissionDetail(dynamic data) {
    final m = _map(data);
    return AdmissionDetail(
      row: admissionRow(m),
      courses: _list(m['courses'])
          .map((c) => AdmissionCourse(id: (c['id']).toString(), name: _str(c['name']) ?? '—'))
          .toList(),
      // v_installment_status columns: due_date, amount_due, status, balance_due
      // (no per-row label/amount) — label synthesised from order.
      installments: _list(m['installments'])
          .asMap()
          .entries
          .map((e) => AdmissionInstallment(
                label: 'Installment ${e.key + 1}',
                amount: _num(e.value['amount_due']),
                paidAmount: _num(e.value['balance_due']),
                dueDate: _date(e.value['due_date']),
                status: _str(e.value['status']),
              ))
          .toList(),
    );
  }

  /// GET /admissions/by-phone/:phone → `{mode:'INTAKE'}` or
  /// `{mode:'ADMISSION', admission_id, undertaking_completed}`.
  static AdmissionPhoneCheck admissionPhoneCheck(dynamic data) {
    final m = _map(data);
    final exists = (_str(m['mode']) ?? '').toUpperCase() == 'ADMISSION';
    return AdmissionPhoneCheck(
      exists: exists,
      admissionId: _str(m['admission_id']),
      undertakingCompleted: m['undertaking_completed'] == null ? null : _bool(m['undertaking_completed']),
    );
  }

  // ── Staff accounts (finance) ────────────────────────────────────────────
  /// GET /accounts/admissions → flat list of `{id(admission_id), name, ...}`.
  static AccountAdmission accountAdmission(Map<String, dynamic> a) => AccountAdmission(
        id: (a['id'] ?? a['admission_id']).toString(),
        name: _str(a['name']) ?? '—',
        admissionNumber: _str(a['admission_number']),
        phoneNumber: _str(a['phone_number']),
        admissionDate: _date(a['admission_date']),
        totalPayable: _num(a['total_payable_amount']),
        totalPaid: _num(a['total_paid']),
        balance: _num(a['balance']),
        approvalStatus: _str(a['approval_status']),
        status: _str(a['status']),
        coursesStr: _str(a['courses_str']),
        certificateName: _str(a['certificate_name']),
        batchName: _str(a['batch_name']),
      );

  static List<AccountAdmission> accountAdmissions(dynamic data) =>
      _list(data).map(accountAdmission).toList();

  static Payment payment(Map<String, dynamic> p) => Payment(
        id: (p['id']).toString(),
        amountPaid: _num(p['amount_paid']),
        paymentDate: _date(p['payment_date']),
        method: _str(p['method']),
        notes: _str(p['notes']),
        receiptNumber: _str(p['receipt_number']),
        collectedBy: _str(p['collected_by']),
      );

  /// GET /accounts/admissions/:id — full account detail.
  static AccountDetails accountDetails(dynamic data) {
    final m = _map(data);
    return AccountDetails(
      name: _str(m['name']) ?? '—',
      fatherName: _str(m['father_name']),
      phone: _str(m['phone']),
      address: _str(m['address']),
      idType: _str(m['id_type']),
      idNumber: _str(m['id_number']),
      admittedBy: _str(m['admitted_by']),
      branch: _str(m['branch']),
      totalFees: _num(m['total_fees']),
      totalPaid: _num(m['total_paid']),
      balance: _num(m['balance']),
      remarks: _str(m['remarks']),
      // Detail installments arrive as {id, due_date, amount, status}.
      installments: _list(m['installments'])
          .map((i) => AdmissionInstallment(
                amount: _num(i['amount']),
                dueDate: _date(i['due_date']),
                status: _str(i['status']),
              ))
          .toList(),
      payments: _list(m['payments']).map(payment).toList(),
      courses: _strings(m['courses']),
      documents: _strings(m['documents']),
    );
  }

  /// GET /accounts/payments/:id/receipt — receipt payload (kept raw + typed).
  /// The controller emits `payment_method` (not `method`) and does not return a
  /// branch/collected-by — those stay null.
  static ReceiptData receiptData(dynamic data) {
    final m = _map(data);
    return ReceiptData(
      raw: m,
      studentName: _str(m['student_name'] ?? m['name']),
      receiptNumber: _str(m['receipt_number']),
      amountPaid: _num(m['amount_paid']),
      paymentDate: _date(m['payment_date']),
      method: _str(m['payment_method'] ?? m['method']),
      notes: _str(m['notes']),
      admissionNumber: _str(m['id_card_no']),
    );
  }

  /// GET /accounts/adjustments → flat list of pending/reviewed adjustments.
  static PaymentAdjustment paymentAdjustment(Map<String, dynamic> a) {
    final pay = a['payment'];
    return PaymentAdjustment(
      id: (a['id']).toString(),
      adjustmentAmount: _num(a['adjustment_amount']),
      reason: _str(a['reason']),
      status: _str(a['status']),
      createdAt: _date(a['created_at']),
      reviewNote: _str(a['review_note']),
      payment: pay is Map ? payment(_map(pay)) : null,
      admissionId: _str(a['admission_id']),
      studentName: _str(a['student_name']),
      studentPhone: _str(a['student_phone']),
      requestedBy: _str(a['requested_by']),
      reviewedBy: _str(a['reviewed_by']),
    );
  }

  static List<PaymentAdjustment> paymentAdjustments(dynamic data) =>
      _list(data).map(paymentAdjustment).toList();

  // ── Staff batch-allotment ───────────────────────────────────────────────
  /// GET /batch-allotment → allotment worklist rows.
  static AllotmentRow allotmentRow(Map<String, dynamic> r) => AllotmentRow(
        admissionId: (r['admission_id']).toString(),
        studentName: _str(r['student_name']) ?? '—',
        admissionNumber: _str(r['admission_number']),
        phoneNumber: _str(r['student_phone_number']),
        courseName: _str(r['course_name']),
        admissionDate: _date(r['admission_date']),
        batchNames: _strings(r['batch_names']),
        joined: _bool(r['joined']),
        joiningDate: _date(r['joining_date']),
        remarks: _str(r['remarks']),
        redFlag: _bool(r['red_flag_status']),
        redFlagReason: _str(r['red_flag_reason']),
        totalDateChanges: _int(r['total_joining_date_changes']) ?? 0,
        remarksCount: _int(r['remarks_count']) ?? 0,
        followUpCount: _int(r['follow_up_count']) ?? 0,
      );

  static List<AllotmentRow> allotmentRows(dynamic data) => _list(data).map(allotmentRow).toList();

  static FollowUp followUp(Map<String, dynamic> f) => FollowUp(
        id: (f['id']).toString(),
        notes: _str(f['notes']),
        status: _str(f['status']),
        type: _str(f['type']),
        followUpDate: _date(f['follow_up_date']),
        nextFollowUpDate: _date(f['next_follow_up_date']),
        createdAt: _date(f['created_at']),
        byUser: _str(_map(f['user'])['username']),
      );

  /// GET /batch-allotment/follow-ups/:id → `{student_name, total_count,
  /// follow_ups:[...]}`.
  static FollowUpHistory followUpHistory(dynamic data) {
    final m = _map(data);
    final list = _list(m['follow_ups']).map(followUp).toList();
    return FollowUpHistory(
      studentName: _str(m['student_name']) ?? '—',
      totalCount: _int(m['total_count']) ?? list.length,
      followUps: list,
    );
  }

  /// POST follow-up → `{success, follow_up:{...}}`.
  static FollowUp followUpOf(dynamic data) =>
      followUp(_map(data is Map && data['follow_up'] != null ? data['follow_up'] : data));

  /// GET /batch-allotment/history/:id → `[{remark_text, created_at, created_by}]`.
  static List<AdmissionRemark> remarkHistory(dynamic data) => _list(data)
      .map((r) => AdmissionRemark(
            text: _str(r['remark_text']),
            createdAt: _date(r['created_at']),
            createdBy: _str(r['created_by']),
          ))
      .toList();

  static RedFlagStudent redFlagStudent(Map<String, dynamic> s) => RedFlagStudent(
        admissionId: (s['admission_id'] ?? s['id']).toString(),
        studentName: _str(s['student_name']) ?? '—',
        admissionNumber: _str(s['admission_number']),
        phoneNumber: _str(s['phone_number'] ?? s['student_phone_number']),
        redFlagReason: _str(s['red_flag_reason']),
        totalDateChanges: _int(s['total_joining_date_changes']) ?? 0,
        remarksCount: _int(s['remarks_count']) ?? 0,
      );

  /// GET /batch-allotment/red-students → flat list.
  static List<RedFlagStudent> redStudents(dynamic data) => _list(data).map(redFlagStudent).toList();

  /// GET /batch-allotment/red-flag-summary → `{total_red_flagged, students:[...]}`.
  static RedFlagSummary redFlagSummary(dynamic data) {
    final m = _map(data);
    return RedFlagSummary(
      totalRedFlagged: _int(m['total_red_flagged']) ?? 0,
      students: _list(m['students']).map(redFlagStudent).toList(),
    );
  }

  // ── Staff follow-ups (collections task list) ────────────────────────────
  static FollowUpTask followUpTask(Map<String, dynamic> t) => FollowUpTask(
        admissionId: (t['admission_id']).toString(),
        studentName: _str(t['student_name']) ?? '—',
        studentPhone: _str(t['student_phone'] ?? t['student_phone_number']),
        admissionNumber: _str(t['admission_number']),
        batchName: _str(t['batch_name']),
        nextDueDate: _date(t['next_task_due_date']),
        totalDue: _num(t['total_due_amount'] ?? t['total_due']),
        taskCount: _int(t['task_count']) ?? 0,
        assignedTo: _str(t['assigned_to']),
        lastLogAt: _date(t['last_log_created_at']),
      );

  /// GET /follow-ups → `{tasks:[...], counts:{today,overdue,upcoming}}`.
  static FollowUpTasksPage followUpTasks(dynamic data) {
    final m = _map(data);
    final counts = _map(m['counts']);
    return FollowUpTasksPage(
      tasks: _list(m['tasks']).map(followUpTask).toList(),
      today: _int(counts['today']) ?? 0,
      overdue: _int(counts['overdue']) ?? 0,
      upcoming: _int(counts['upcoming']) ?? 0,
    );
  }

  /// GET /follow-ups/history/:id → `[{...follow_up_details, staff_name}]`. The
  /// `follow_up_details` view ALIASES its columns — id→follow_up_id,
  /// notes→follow_up_notes, type→follow_up_type, created_at→log_date — so read
  /// those first (fallbacks keep it robust to a raw follow_ups row).
  static List<FollowUpLog> followUpLogs(dynamic data) => _list(data)
      .map((l) => FollowUpLog(
            id: (l['follow_up_id'] ?? l['id']).toString(),
            date: _date(l['log_date'] ?? l['follow_up_date'] ?? l['created_at']),
            notes: _str(l['follow_up_notes'] ?? l['notes']),
            type: _str(l['follow_up_type'] ?? l['type']),
            leadType: _str(l['lead_type']),
            nextFollowUpDate: _date(l['next_follow_up_date']),
            staffName: _str(l['staff_name']),
          ))
      .toList();

  // ── Staff faculty (HR) ──────────────────────────────────────────────────
  /// GET /faculty → transformed rows (mixed camelCase leave keys + snake else).
  static Faculty faculty(Map<String, dynamic> f) => Faculty(
        id: (f['id']).toString(),
        name: _str(f['name']) ?? '—',
        email: _str(f['email']),
        phoneNumber: _str(f['phone_number']),
        employmentType: _str(f['type'] ?? f['employment_type']),
        isActive: f['isActive'] == null ? _bool(f['is_active']) : _bool(f['isActive']),
        locationId: _int(f['location_id']),
        status: _str(f['status']),
        leaveStartDate: _date(f['leaveStartDate'] ?? f['leave_start_date']),
        leaveEndDate: _date(f['leaveEndDate'] ?? f['leave_end_date']),
        leaveReason: _str(f['leaveReason'] ?? f['leave_reason']),
        skills: _list(f['skills'])
            .map((s) => FacultySkill(id: (s['id']).toString(), name: _str(s['name']) ?? ''))
            .toList(),
        availability: _list(f['availability'])
            .map((a) => FacultyAvailability(
                  id: _str(a['id']),
                  dayOfWeek: _str(a['day_of_week']),
                  startTime: _str(a['start_time']),
                  endTime: _str(a['end_time']),
                ))
            .toList(),
      );

  static List<Faculty> faculties(dynamic data) => _list(data).map(faculty).toList();

  // ── Staff substitutions ─────────────────────────────────────────────────
  static NamedRef? _namedRef(dynamic v) {
    if (v is! Map) return null;
    final m = _map(v);
    return NamedRef(id: (m['id']).toString(), name: _str(m['name']) ?? '—');
  }

  /// GET /substitution/temporary → `[{id, start_date, end_date, notes,
  /// original_faculty:{id,name}, substitute_faculty:{id,name}, batch_name,
  /// batch_id}]`.
  static Substitution substitution(Map<String, dynamic> s) => Substitution(
        id: (s['id']).toString(),
        batchId: _str(s['batch_id']),
        batchName: _str(s['batch_name']),
        startDate: _date(s['start_date']),
        endDate: _date(s['end_date']),
        notes: _str(s['notes']),
        originalFaculty: _namedRef(s['original_faculty']),
        substituteFaculty: _namedRef(s['substitute_faculty']),
      );

  static List<Substitution> substitutions(dynamic data) => _list(data).map(substitution).toList();

  /// GET /availability/faculty/:id (or POST /availability response) →
  /// `[{id, day_of_week, start_time, end_time}]`.
  static List<FacultyAvailability> availabilitySlots(dynamic data) => _list(data)
      .map((a) => FacultyAvailability(
            id: _str(a['id']),
            dayOfWeek: _str(a['day_of_week']),
            startTime: _str(a['start_time']),
            endTime: _str(a['end_time']),
          ))
      .toList();

  static Faculty facultyOf(dynamic data) => faculty(_map(data));

  /// GET /faculty/active-students → `[{faculty_id, active_students}]`.
  static Map<String, int> facultyActiveStudents(dynamic data) => {
        for (final m in _list(data)) (m['faculty_id']).toString(): _int(m['active_students']) ?? 0,
      };

  /// GET /faculty/student-counts → `[{faculty_id, total_students}]`.
  static Map<String, int> facultyStudentCounts(dynamic data) => {
        for (final m in _list(data)) (m['faculty_id']).toString(): _int(m['total_students']) ?? 0,
      };

  /// GET /faculty/total-students/:id → `{total_students, students:[ids]}`.
  static FacultyTotalStudents facultyTotalStudents(dynamic data) {
    final m = _map(data);
    return FacultyTotalStudents(
      total: _int(m['total_students']) ?? 0,
      studentIds: _strings(m['students']),
    );
  }

  /// GET /follow-ups/staff-report → `{report:[{staff_name,count,logs:[...]}], total}`.
  static StaffFollowUpReport staffFollowUpReport(dynamic data) {
    final m = _map(data);
    return StaffFollowUpReport(
      total: _int(m['total']) ?? 0,
      entries: _list(m['report'])
          .map((e) => StaffFollowUpEntry(
                staffName: _str(e['staff_name']) ?? 'System',
                count: _int(e['count']) ?? 0,
                logs: _list(e['logs'])
                    .map((l) => StaffFollowUpLog(
                          id: (l['id']).toString(),
                          date: _date(l['date']),
                          notes: _str(l['notes']),
                          type: _str(l['type']),
                          leadType: _str(l['lead_type']),
                          nextFollowUpDate: _date(l['next_follow_up_date']),
                          studentName: _str(l['student_name']),
                          studentPhone: _str(l['student_phone']),
                          admissionNumber: _str(l['admission_number']),
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }

  // ── Staff support tickets ───────────────────────────────────────────────
  /// A `users`-shaped ref whose display name is the `username` column.
  static NamedRef? _userRef(dynamic v) {
    if (v is! Map) return null;
    final m = _map(v);
    return NamedRef(id: (m['id']).toString(), name: _str(m['username']) ?? _str(m['name']) ?? '—');
  }

  /// GET /tickets item / GET /tickets/:id → ticket with nested student +
  /// assignee. The list flattens `student_ticket_count` onto the row.
  static StaffTicket ticket(Map<String, dynamic> t) => StaffTicket(
        id: (t['id']).toString(),
        title: _str(t['title']) ?? '',
        description: _str(t['description']),
        status: _str(t['status']) ?? 'Open',
        priority: _str(t['priority']) ?? 'Medium',
        category: _str(t['category']),
        createdAt: _date(t['created_at']),
        updatedAt: _date(t['updated_at']),
        student: _namedRef(t['student']),
        assignee: _userRef(t['assignee']),
        assigneeId: _str(t['assignee_id']),
        studentTicketCount: _int(t['student_ticket_count']) ?? 0,
      );

  static StaffTicket ticketOf(dynamic data) => ticket(_map(data));

  /// GET /tickets → `{items, total, counts:{All,Open,'In Progress',Resolved},
  /// page, limit}`.
  static TicketsPage ticketsPage(dynamic data) {
    final m = _map(data);
    final c = _map(m['counts']);
    return TicketsPage(
      items: _list(m['items']).map(ticket).toList(),
      total: _int(m['total']) ?? 0,
      counts: TicketCounts(
        all: _int(c['All']) ?? 0,
        open: _int(c['Open']) ?? 0,
        inProgress: _int(c['In Progress']) ?? 0,
        resolved: _int(c['Resolved']) ?? 0,
      ),
      page: _int(m['page']) ?? 1,
      limit: _int(m['limit']) ?? 15,
    );
  }

  /// GET /tickets/:ticketId/chat → `[{id, message, created_at, sender_user_id,
  /// sender_student_id, user:{id,username}, student:{id,name}}]`.
  static TicketMessage ticketMessage(Map<String, dynamic> m) => TicketMessage(
        id: (m['id']).toString(),
        message: _str(m['message']) ?? '',
        createdAt: _date(m['created_at']),
        senderUserId: _str(m['sender_user_id']),
        senderStudentId: _str(m['sender_student_id']),
        user: _userRef(m['user']),
        student: _namedRef(m['student']),
      );

  static List<TicketMessage> ticketMessages(dynamic data) => _list(data).map(ticketMessage).toList();

  /// GET /tickets/admins → `[{id, username}]`.
  static List<NamedRef> ticketAdmins(dynamic data) => _list(data)
      .map((a) => NamedRef(id: (a['id']).toString(), name: _str(a['username']) ?? '—'))
      .toList();

  /// GET /tickets/categories → a plain array of category names.
  static List<String> ticketCategories(dynamic data) => _strings(data);

  // ── CEO command centre ───────────────────────────────────────────────────
  static Map<String, num> _numMap(dynamic v) => {
        for (final e in _map(v).entries) e.key: _num(e.value) ?? 0,
      };
  static Map<String, int> _intMap(dynamic v) => {
        for (final e in _map(v).entries) e.key: _int(e.value) ?? 0,
      };

  /// GET /ceo/dashboard → `{overview, finance, operations, support}`.
  static CeoDashboard ceoDashboard(dynamic data) {
    final m = _map(data);
    final o = _map(m['overview']);
    final f = _map(m['finance']);
    final op = _map(m['operations']);
    return CeoDashboard(
      overview: CeoOverview(
        totalStudents: _int(o['totalStudents']) ?? 0,
        studentsJoined: _int(o['studentsJoined']) ?? 0,
        activeBatches: _int(o['activeBatches']) ?? 0,
        totalFaculty: _int(o['totalFaculty']) ?? 0,
        activeFaculty: _int(o['activeFaculty']) ?? 0,
        onLeaveFaculty: _int(o['onLeaveFaculty']) ?? 0,
      ),
      finance: CeoFinance(
        revenueInPeriod: _num(f['revenueInPeriod']) ?? 0,
        predictedRevenue: _num(f['predictedRevenue']) ?? 0,
        totalOutstandingDebt: _num(f['totalOutstandingDebt']) ?? 0,
        paymentMethods: _numMap(f['paymentMethods']),
      ),
      operations: CeoOperations(
        overdueFollowUps: _int(op['overdueFollowUps']) ?? 0,
        admissionStatus: _intMap(op['admissionStatus']),
      ),
    );
  }

  /// GET /ceo/trends → `[{date, admissions, joined, revenue, ticketsOpened,
  /// ticketsResolved}]`.
  static List<CeoTrendPoint> ceoTrends(dynamic data) => _list(data)
      .map((t) => CeoTrendPoint(
            date: _str(t['date']) ?? '',
            admissions: _int(t['admissions']) ?? 0,
            joined: _int(t['joined']) ?? 0,
            revenue: _num(t['revenue']) ?? 0,
            ticketsOpened: _int(t['ticketsOpened']) ?? 0,
            ticketsResolved: _int(t['ticketsResolved']) ?? 0,
          ))
      .toList();

  /// GET /ceo/collection-rate-intelligence → scalar KPIs + comparison block.
  static CeoCollectionIntel ceoCollectionIntel(dynamic data) {
    final m = _map(data);
    final c = _map(m['comparison']);
    return CeoCollectionIntel(
      collectionRate: _num(m['collectionRate']) ?? 0,
      totalReceiptsAmount: _num(m['totalReceiptsAmount']) ?? 0,
      revenueGap: _num(m['revenueGap']) ?? 0,
      expectedRevenueBenchmark: _num(m['expectedRevenueBenchmark']) ?? 0,
      avgAdmissions3Mo: _num(m['avgAdmissions3Mo']) ?? 0,
      prevCollectionRate: _num(c['prevCollectionRate']) ?? 0,
      changeAmount: _num(c['changeAmount']) ?? 0,
      changePct: _num(c['changePct']) ?? 0,
    );
  }

  /// GET /ceo/faculty-attendance → `{yesterday_snapshot:{...}, date}`.
  static CeoFacultyAttendance ceoFacultyAttendance(dynamic data) {
    final m = _map(data);
    final s = _map(m['yesterday_snapshot']);
    return CeoFacultyAttendance(
      date: _str(m['date']) ?? _str(s['snapshot_date']),
      totalFaculty: _int(s['total_faculty']) ?? 0,
      presentCount: _int(s['present_count']) ?? 0,
      absentCount: _int(s['absent_count']) ?? 0,
      attendancePct: _num(s['attendance_pct']) ?? 0,
      isLive: _bool(s['is_live']),
    );
  }

  // ── Staff dashboard ─────────────────────────────────────────────────────
  /// Reads `{ metrics:{...}, admissions:[...] }`; the backend uses camelCase keys.
  static DashboardMetrics dashboardMetrics(dynamic data) {
    final root = _map(data);
    final m = root['metrics'] is Map ? _map(root['metrics']) : root;
    return DashboardMetrics(
      totalAdmissions: _int(m['totalAdmissions']) ?? 0,
      admissionsThisMonth: _int(m['admissionsThisMonth']) ?? 0,
      totalCollected: _num(m['totalCollected']) ?? 0,
      totalOutstanding: _num(m['totalOutstanding']) ?? 0,
      overdueCount: _int(m['overdueCount']) ?? 0,
      pendingUndertakings: _int(m['pendingUndertakings']) ?? 0,
    );
  }

  /// GET /dashboard/yesterday-attendance → `{ attendance: <int> }`.
  static int yesterdayAttendance(dynamic data) => _int(_map(data)['attendance']) ?? 0;

  // ── Attendance ──────────────────────────────────────────────────────────
  /// GET /attendance/batch/:id/daily → flat list of rows, each carrying the
  /// nested `student` + eligibility flags synthesised by the controller.
  static AttendanceEntry attendanceEntry(Map<String, dynamic> r) {
    final s = _map(r['student']);
    return AttendanceEntry(
      studentId: (r['student_id'] ?? s['id']).toString(),
      studentName: _str(s['name']) ?? '—',
      isPresent: _bool(r['is_present']),
      admissionNumber: _str(s['admission_number']),
      phoneNumber: _str(s['phone_number']),
      // Absent-only rows may omit is_eligible; default eligible so they show.
      isEligible: r['is_eligible'] == null ? true : _bool(r['is_eligible']),
      isOnHold: _bool(r['is_on_hold']),
      notYetJoined: _bool(r['not_yet_joined']),
      isPlaceholder: _bool(r['is_placeholder']),
      absentReason: _str(r['absent_reason']),
      followUpComment: _str(r['follow_up_comment']),
    );
  }

  static List<AttendanceEntry> dailyRoster(dynamic data) =>
      _list(data).map(attendanceEntry).toList();

  static AttendanceHistoryEntry? _historyEntry(Map<String, dynamic> h) {
    final d = _date(h['date']);
    if (d == null) return null;
    return AttendanceHistoryEntry(
      date: d,
      isPresent: _bool(h['is_present']),
      absentReason: _str(h['absent_reason']),
      followUpComment: _str(h['follow_up_comment']),
      remarksUpdatedBy: _str(h['remarks_updated_by']),
    );
  }

  /// GET /attendance/batch/:id/student/:sid/history → bare list of sessions.
  static List<AttendanceHistoryEntry> historyList(dynamic data) =>
      _list(data).map(_historyEntry).whereType<AttendanceHistoryEntry>().toList();

  /// GET /attendance/batch/:id/history → `{ [studentId]: [session, ...] }`.
  static Map<String, List<AttendanceHistoryEntry>> batchHistory(dynamic data) {
    final m = _map(data);
    return m.map((k, v) => MapEntry(
        k, _list(v).map(_historyEntry).whereType<AttendanceHistoryEntry>().toList()));
  }

  /// GET /attendance/batch/:id/pending-remarks → `{ records:[...] }` with a
  /// trimmed `student` (id/name/admission_number).
  static List<PendingRemark> batchPendingRemarks(dynamic data) {
    final list = data is Map ? data['records'] : data;
    return _list(list).map((r) {
      final s = _map(r['student']);
      return PendingRemark(
        attendanceId: (r['id']).toString(),
        studentId: (r['student_id'] ?? s['id']).toString(),
        studentName: _str(s['name']) ?? '—',
        date: _date(r['date']),
        admissionNumber: _str(s['admission_number']),
        absentReason: _str(r['absent_reason']),
        attendancePercentage: _int(r['attendance_percentage']),
      );
    }).toList();
  }

  /// GET /attendance/pending-remarks/batches → `{ date, total_pending,
  /// batches:[{...students:[...]}] }` (single-day shape).
  static List<PendingRemarksGroup> pendingRemarksGroups(dynamic data) {
    final list = data is Map ? data['batches'] : data;
    return _list(list).map((g) {
      final bid = (g['batch_id']).toString();
      final bname = _str(g['batch_name']) ?? '—';
      return PendingRemarksGroup(
        batchId: bid,
        batchName: bname,
        pendingCount: _int(g['pending_count']) ?? 0,
        locationId: _int(g['location_id']),
        startTime: _str(g['start_time']),
        students: _list(g['students'])
            .map((e) => PendingRemark(
                  attendanceId: (e['attendance_id']).toString(),
                  studentId: (e['student_id']).toString(),
                  studentName: _str(e['student_name']) ?? '—',
                  date: _date(e['date']),
                  admissionNumber: _str(e['admission_number']),
                  phoneNumber: _str(e['phone_number']),
                  absentReason: _str(e['absent_reason']),
                  followUpComment: _str(e['follow_up_comment']),
                  attendancePercentage: _int(e['attendance_percentage']),
                  batchId: bid,
                  batchName: bname,
                ))
            .toList(),
      );
    }).toList();
  }

  /// GET /attendance/today-summary → `{ overall_attendance_percentage:num? }`.
  static double? todayAttendancePercentage(dynamic data) =>
      _num(_map(data)['overall_attendance_percentage'])?.toDouble();

  static FacultyBatchLine _facultyBatchLine(Map<String, dynamic> b) {
    final c = _map(b['compliance']);
    return FacultyBatchLine(
      batchId: (b['batch_id']).toString(),
      batchName: _str(b['batch_name']) ?? '—',
      status: _str(b['status']),
      studentCount: _int(b['student_count']),
      expectedSessions: _int(b['expected_sessions']),
      // faculty report uses marked_sessions; compliance uses total_sessions.
      markedSessions: _int(b['marked_sessions'] ?? b['total_sessions']),
      percentage: _num(b['attendance_percentage'])?.toDouble(),
      missingDates: _strings(c['missing_attendance_dates']),
      isComplete: b['compliance'] == null ? true : _bool(c['is_complete']),
    );
  }

  static MissingLog _missingLog(Map<String, dynamic> m) =>
      MissingLog(batchName: _str(m['batch_name']) ?? '—', count: _int(m['count']) ?? 0);

  /// GET /attendance/reports/overall.
  static OverallAttendanceReport overallReport(dynamic data) {
    final m = _map(data);
    return OverallAttendanceReport(
      overallPercentage: (_num(m['overall_attendance_percentage']) ?? 0).toDouble(),
      totalExpected: _int(m['total_expected_records']) ?? 0,
      totalPresent: _int(m['total_present']) ?? 0,
      locations: _list(m['location_breakdown'])
          .map((l) => LocationAttendance(
                locationId: _int(l['location_id']),
                totalExpected: _int(l['total_expected_records']) ?? 0,
                totalPresent: _int(l['total_present']) ?? 0,
                percentage: _num(l['attendance_percentage'])?.toDouble(),
              ))
          .toList(),
    );
  }

  /// GET /attendance/reports/faculty/:id.
  static FacultyAttendanceReport facultyReport(dynamic data) {
    final m = _map(data);
    return FacultyAttendanceReport(
      facultyId: (m['faculty_id']).toString(),
      facultyName: _str(m['faculty_name']) ?? '—',
      percentage: _num(m['faculty_attendance_percentage'])?.toDouble(),
      batches: _list(m['batches']).map(_facultyBatchLine).toList(),
      missingLogs: _list(m['missing_logs']).map(_missingLog).toList(),
    );
  }

  /// GET /attendance/reports/compliance.
  static ComplianceReport complianceReport(dynamic data) {
    final m = _map(data);
    return ComplianceReport(
      overallPercentage: (_num(m['overall_attendance_percentage']) ?? 0).toDouble(),
      faculties: _list(m['faculty_reports'])
          .map((f) => ComplianceFacultyLine(
                facultyId: (f['faculty_id']).toString(),
                facultyName: _str(f['faculty_name']) ?? '—',
                locationId: _int(f['location_id']),
                percentage: _num(f['faculty_attendance_percentage'])?.toDouble(),
                batches: _list(f['batches']).map(_facultyBatchLine).toList(),
                missingLogs: _list(f['missing_logs']).map(_missingLog).toList(),
              ))
          .toList(),
    );
  }

  /// GET /attendance/reports/batch/:id — students + session compliance counts.
  static BatchAttendanceReport batchReport(dynamic data) {
    final m = _map(data);
    final c = _map(m['compliance']);
    return BatchAttendanceReport(
      students: _list(m['students'])
          .map((s) => BatchReportStudent(
                id: (s['id']).toString(),
                name: _str(s['name']) ?? '—',
                admissionNumber: _str(s['admission_number']),
                phoneNumber: _str(s['phone_number']),
                remarks: _str(s['remarks']),
                totalDue: _num(s['total_due_amount']),
                isDefaulter: _bool(s['is_defaulter']),
                isBanned: _bool(s['is_banned']),
                isSuspended: _bool(s['is_suspended']),
              ))
          .toList(),
      expectedDays: _int(c['expected_days_count']) ?? 0,
      markedDays: _int(c['marked_days_count']) ?? 0,
    );
  }

  // ── Support tickets ─────────────────────────────────────────────────────
  static SupportTicket supportTicket(Map<String, dynamic> m) => SupportTicket(
        id: m['id'].toString(),
        subject: _str(m['subject']) ?? '',
        status: parseTicketStatus(_str(m['status'])),
        createdAt: _date(m['created_at']),
        updatedAt: _date(m['updated_at']),
      );

  static List<SupportTicket> supportTickets(dynamic data) =>
      _list(data is Map ? data['tickets'] : data).map(supportTicket).toList();

  static TicketReply ticketReply(Map<String, dynamic> m) => TicketReply(
        id: m['id'].toString(),
        message: _str(m['message']) ?? '',
        senderRole: _str(m['sender_role']),
        createdAt: _date(m['created_at']),
      );

  static TicketDetail ticketDetail(Map<String, dynamic> m) => TicketDetail(
        id: m['id'].toString(),
        subject: _str(m['subject']) ?? '',
        status: parseTicketStatus(_str(m['status'])),
        message: _str(m['message']),
        createdAt: _date(m['created_at']),
        updatedAt: _date(m['updated_at']),
        replies: _list(m['replies']).map(ticketReply).toList(),
      );

  // ── Companies (public) ──────────────────────────────────────────────────
  static Company company(Map<String, dynamic> m) => Company(
        id: m['id'].toString(),
        name: _str(m['name']) ?? '',
        industry: _str(m['industry']),
        size: _str(m['size']),
        city: _str(m['city']),
        state: _str(m['state']),
        website: _str(m['website']),
        logoUrl: _str(m['logo_url']),
        verified: (_str(m['approval_status']) ?? '').toLowerCase().contains('approved'),
        jobCount: _int(m['job_count']),
      );

  static List<Company> companies(dynamic data) =>
      _list(data is Map ? data['companies'] : data).map(company).toList();

  // ── Work experience stack ───────────────────────────────────────────────
  static ExperienceEntry experienceEntry(Map<String, dynamic> m) => ExperienceEntry(
        id: m['id'].toString(),
        jobDomain: _str(m['job_domain']) ?? '',
        companyName: _str(m['company_name']),
        industry: _str(m['industry']),
        jobRole: _str(m['job_role']),
        skills: _strings(m['skills']),
        durationMonths: _int(m['duration_months']),
        isCurrent: _bool(m['is_current']),
        startDate: _date(m['start_date']),
        endDate: _date(m['end_date']),
        source: _str(m['source']),
        createdAt: _date(m['created_at']),
      );

  /// GET returns `{ experience_stack:[...] }`; write endpoints return
  /// `{ entry:{...} }` — [experienceEntryOf] unwraps the latter.
  static List<ExperienceEntry> experienceStack(dynamic data) =>
      _list(data is Map ? data['experience_stack'] : data).map(experienceEntry).toList();

  static ExperienceEntry experienceEntryOf(dynamic data) =>
      experienceEntry(_map(data is Map && data['entry'] != null ? data['entry'] : data));

  // ── Certifications ──────────────────────────────────────────────────────
  static Certification certification(Map<String, dynamic> m) => Certification(
        id: m['id'].toString(),
        name: _str(m['name']) ?? '',
        issuingAuthority: _str(m['issuing_authority']),
        issueDate: _str(m['issue_date']),
        durationMonths: _int(m['duration_months']),
        hasCertificate: _bool(m['has_certificate']) || _str(m['signed_url']) != null,
        signedUrl: _str(m['signed_url']),
        createdAt: _date(m['created_at']),
      );

  static List<Certification> certifications(dynamic data) =>
      _list(data is Map ? data['certifications'] : data).map(certification).toList();

  // ── Registration reference data (taxonomy + India locations) ─────────────
  static List<TaxonomyIndustry> taxonomy(dynamic data) =>
      _list(data is Map ? data['industries'] : data)
          .map((i) => TaxonomyIndustry(
                industry: _str(i['industry']) ?? '',
                domains: _list(i['domains'])
                    .map((d) => TaxonomyDomain(
                          domain: _str(d['domain']) ?? '',
                          roles: _list(d['roles'])
                              .map((r) => TaxonomyRole(
                                    role: _str(r['role']) ?? '',
                                    skills: _strings(r['skillsRequired']),
                                  ))
                              .where((r) => r.role.isNotEmpty)
                              .toList(),
                        ))
                    .where((d) => d.domain.isNotEmpty)
                    .toList(),
              ))
          .where((i) => i.industry.isNotEmpty)
          .toList();

  static List<IndiaState> indiaStates(dynamic data) =>
      _list(data is Map ? data['states'] : data)
          .map((s) => IndiaState(name: _str(s['name']) ?? '', code: _str(s['code']) ?? ''))
          .where((s) => s.name.isNotEmpty && s.code.isNotEmpty)
          .toList();

  static List<String> cityNames(dynamic data) =>
      _strings(data is Map ? data['cities'] : data);

  // ── Feedback ────────────────────────────────────────────────────────────
  static FeedbackItem feedbackItem(Map<String, dynamic> m) => FeedbackItem(
        id: m['id'].toString(),
        type: parseFeedbackType(_str(m['feedback_type'])),
        title: _str(m['title']) ?? '',
        description: _str(m['description']),
        status: _str(m['status']),
        createdAt: _date(m['created_at']),
      );

  /// GET /feedback → `{ items:[...] }`.
  static List<FeedbackItem> feedbackItems(dynamic data) =>
      _list(data is Map ? data['items'] : data).map(feedbackItem).toList();

  // ── Skill suggestions (autocomplete) ────────────────────────────────────
  static List<SkillSuggestion> skillSuggestions(dynamic data) =>
      _list(data is Map ? data['suggestions'] : data)
          .map((s) => SkillSuggestion(
                name: _str(s['name']) ?? '',
                id: _str(s['id']),
                category: _str(s['category']),
                usageCount: _int(s['usage_count']),
              ))
          .where((s) => s.name.isNotEmpty)
          .toList();

  // ── Candidate ↔ admin chat ──────────────────────────────────────────────
  static ChatMessage chatMessage(Map<String, dynamic> m) => ChatMessage(
        id: m['id'].toString(),
        content: _str(m['content']) ?? '',
        fromCandidate: (_str(m['sender_type']) ?? '').toLowerCase() == 'candidate',
        isRead: _bool(m['is_read']),
        createdAt: _date(m['created_at']),
      );

  /// GET returns `{ conversation_id, messages:[...] }`.
  static ChatThread chatThread(dynamic data) {
    final m = _map(data);
    return ChatThread(
      conversationId: _str(m['conversation_id']),
      messages: _list(m['messages']).map(chatMessage).toList(),
    );
  }

  // ── JobPortal candidate announcements (audience-filtered) ────────────────
  static AnnouncementItem candidateAnnouncement(Map<String, dynamic> a) => AnnouncementItem(
        id: a['id'].toString(),
        title: _str(a['title']) ?? '',
        category: AnnouncementCategory.institute,
        body: _str(a['body']),
        createdAt: _date(a['created_at']),
      );

  static List<AnnouncementItem> candidateAnnouncements(dynamic data) =>
      _list(data).map(candidateAnnouncement).toList();

  // ── RVM verification (flag-gated) ───────────────────────────────────────
  static RvmVerification rvmVerification(Map<String, dynamic> m) => RvmVerification(
        id: m['id'].toString(),
        status: _str(m['status']) ?? 'pending_review',
        trainingStartDate: _str(m['training_start_date']),
        trainingEndDate: _str(m['training_end_date']),
        industry: _str(m['industry']),
        jobDomain: _str(m['job_domain']),
        jobRole: _str(m['job_role']),
        skills: _strings(m['skills']),
        certificateFileName: _str(m['certificate_file_name']),
        submittedAt: _date(m['submitted_at']),
        reviewedAt: _date(m['reviewed_at']),
        adminNotes: _str(m['admin_notes']),
        rejectionReason: _str(m['rejection_reason']),
      );

  static RvmVerificationStatus rvmVerificationStatus(dynamic data) {
    final m = _map(data);
    final v = m['verification'];
    return RvmVerificationStatus(
      featureEnabled: _bool(m['feature_enabled']),
      verification: v is Map ? rvmVerification(_map(v)) : null,
    );
  }

  // ── Public active offer ─────────────────────────────────────────────────
  static Offer? activeOffer(dynamic data) {
    final offer = _map(data)['offer'];
    if (offer is! Map) return null;
    final m = _map(offer);
    return Offer(
      id: m['id'].toString(),
      name: _str(m['name']) ?? '',
      message: _str(m['message']),
      pricePaise: _int(m['price_paise']),
      validTo: _date(m['valid_to']),
    );
  }
}
