/// Scheduler certificate catalog — the named certificates (with a cost) that
/// admissions can attach. A simple admin-managed CRUD list.
class Certificate {
  const Certificate({required this.id, required this.name, this.cost});

  final String id;
  final String name;
  final num? cost;
}

/// Create/update payload for POST/PUT /certificates. The backend requires a
/// non-negative [cost]; both fields are sent (the edit form shows both, so
/// re-sending is lossless).
class CertificateDraft {
  const CertificateDraft({required this.name, required this.cost});

  final String name;
  final num cost;

  Map<String, dynamic> toJson() => {'name': name, 'cost': cost};
}
