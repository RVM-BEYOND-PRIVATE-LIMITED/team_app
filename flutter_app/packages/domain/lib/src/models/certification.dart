/// A candidate certification (GET/POST/DELETE /candidates/certifications).
/// [signedUrl] is a short-lived download link the backend mints per GET.
class Certification {
  const Certification({
    required this.id,
    required this.name,
    this.issuingAuthority,
    this.issueDate,
    this.durationMonths,
    this.hasCertificate = false,
    this.signedUrl,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? issuingAuthority;

  /// Stored as `YYYY-MM`.
  final String? issueDate;
  final int? durationMonths;

  /// Whether a certificate file is attached (a signed download URL exists).
  final bool hasCertificate;
  final String? signedUrl;
  final DateTime? createdAt;
}
