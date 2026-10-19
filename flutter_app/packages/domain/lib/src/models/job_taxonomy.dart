/// Industry → Domain → Role → Skills taxonomy that drives the registration
/// cascading pickers. Fetched from the JobPortal public endpoint so the app
/// stays in sync with the website's source of truth.
class TaxonomyRole {
  const TaxonomyRole({required this.role, required this.skills});
  final String role;
  final List<String> skills;
}

class TaxonomyDomain {
  const TaxonomyDomain({required this.domain, required this.roles});
  final String domain;
  final List<TaxonomyRole> roles;
}

class TaxonomyIndustry {
  const TaxonomyIndustry({required this.industry, required this.domains});
  final String industry;
  final List<TaxonomyDomain> domains;
}

/// An Indian state for the location pickers: display [name] + ISO [code] (the
/// code is what the cities lookup expects).
class IndiaState {
  const IndiaState({required this.name, required this.code});
  final String name;
  final String code;
}
