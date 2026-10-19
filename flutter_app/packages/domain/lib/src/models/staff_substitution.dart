/// Scheduler faculty-substitution domain — temporary substitutions (a stand-in
/// faculty covers a batch for a date range), plus the permanent-reassign and
/// batch-merge operations. Admin-only.

/// A named id reference (faculty).
class NamedRef {
  const NamedRef({required this.id, required this.name});
  final String id;
  final String name;
}

/// An active temporary substitution.
class Substitution {
  const Substitution({
    required this.id,
    this.batchId,
    this.batchName,
    this.startDate,
    this.endDate,
    this.notes,
    this.originalFaculty,
    this.substituteFaculty,
  });

  final String id;
  final String? batchId;
  final String? batchName;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final NamedRef? originalFaculty;
  final NamedRef? substituteFaculty;
}

// ── Write payloads ───────────────────────────────────────────────────────────

/// POST /substitution/temporary.
class SubstitutionDraft {
  const SubstitutionDraft({
    required this.batchId,
    required this.substituteFacultyId,
    required this.startDate,
    required this.endDate,
    this.notes,
  });

  final String batchId;
  final String substituteFacultyId;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'substituteFacultyId': substituteFacultyId,
        'startDate': _ymd(startDate),
        'endDate': _ymd(endDate),
        if (notes != null) 'notes': notes,
      };
}

/// PUT /substitution/temporary/:id.
class SubstitutionUpdate {
  const SubstitutionUpdate({
    required this.substituteFacultyId,
    required this.startDate,
    required this.endDate,
    this.notes,
  });

  final String substituteFacultyId;
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'substituteFacultyId': substituteFacultyId,
        'startDate': _ymd(startDate),
        'endDate': _ymd(endDate),
        // Sent unconditionally: the backend treats an absent key as "keep the
        // old note" and "" as "clear it", so an emptied field must send "".
        'notes': notes ?? '',
      };
}
