/// Result of a password login / reset-set / setup-set. On success the backend
/// has set the `rvm_session` cookie; [banned] tells the app to route the user
/// to the ban-appeal flow instead of signing in.
class PasswordAuthResult {
  const PasswordAuthResult({
    this.userId,
    this.role,
    this.redirectTo,
    this.banned = false,
    this.banType,
  });

  final String? userId;
  final String? role;

  /// Backend web redirect target (informational on mobile).
  final String? redirectTo;
  final bool banned;
  final String? banType;

  /// True when the backend routes the user into the registration flow (their
  /// profile isn't complete yet) — the app should open registration, not home.
  bool get needsRegistration => redirectTo?.contains('/register') ?? false;
}
