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
}
