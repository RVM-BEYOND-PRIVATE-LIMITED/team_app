/// A recent activity-feed entry (GET /activities → newest 10, branch-scoped).
class Activity {
  const Activity({this.action, this.item, this.type, this.createdAt});
  final String? action;
  final String? item;
  final String? type;
  final DateTime? createdAt;
}
