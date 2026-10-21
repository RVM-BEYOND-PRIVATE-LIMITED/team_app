import 'dart:convert';

/// Decodes a JWT's payload WITHOUT verifying the signature — the Scheduler has
/// no `/me`, so on relaunch we read the claims from the stored token to restore
/// the session. Signature verification is the server's job; we only read claims.
/// Never throws — returns an empty map for a malformed/absent token.
abstract final class Jwt {
  static Map<String, dynamic> decodePayload(String? token) {
    if (token == null || token.isEmpty) return const {};
    final parts = token.split('.');
    if (parts.length != 3) return const {};
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = json.decode(decoded);
      return map is Map ? Map<String, dynamic>.from(map) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// True only when the token carries an `exp` claim that is already in the
  /// past. A token with no readable `exp` is left to the server to judge, so a
  /// malformed or opaque token is never treated as expired here.
  static bool isExpired(String? token, {DateTime? now}) {
    final exp = decodePayload(token)['exp'];
    if (exp is! num) return false;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
        .isBefore(now ?? DateTime.now());
  }
}
