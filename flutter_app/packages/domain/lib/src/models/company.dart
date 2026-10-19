/// A hiring company, as the public companies browse/detail screens show it.
class Company {
  const Company({
    required this.id,
    required this.name,
    this.industry,
    this.size,
    this.city,
    this.state,
    this.website,
    this.logoUrl,
    this.verified = false,
    this.jobCount,
  });

  final String id;
  final String name;
  final String? industry;
  final String? size;
  final String? city;
  final String? state;
  final String? website;
  final String? logoUrl;
  final bool verified;
  final int? jobCount;

  String? get location =>
      [city, state].where((e) => e != null && e.isNotEmpty).join(', ').ifEmpty();
}

extension on String {
  String? ifEmpty() => isEmpty ? null : this;
}
