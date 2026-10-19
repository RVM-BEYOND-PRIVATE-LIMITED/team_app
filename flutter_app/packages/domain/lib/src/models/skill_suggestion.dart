/// One autocomplete hit from GET /candidates/skill-suggestions?q=…
/// (drawn from the shared job_skill_tags catalogue).
class SkillSuggestion {
  const SkillSuggestion({required this.name, this.id, this.category, this.usageCount});

  final String name;
  final String? id;
  final String? category;
  final int? usageCount;
}
