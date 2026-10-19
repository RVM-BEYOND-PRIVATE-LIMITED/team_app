/// Scheduler skill catalog — the named, categorised skills (branch-scoped) that
/// faculty and batches reference. A simple admin-managed CRUD list.
class Skill {
  const Skill({
    required this.id,
    required this.name,
    this.category,
    this.description,
    this.locationId,
  });

  final String id;
  final String name;
  final String? category;
  final String? description;
  final int? locationId;
}

/// Create/update payload for POST/PUT /skills. Name + category are required;
/// [description] is sent unconditionally so an emptied field clears server-side.
class SkillDraft {
  const SkillDraft({required this.name, required this.category, this.description});

  final String name;
  final String category;
  final String? description;

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'description': description,
      };
}
