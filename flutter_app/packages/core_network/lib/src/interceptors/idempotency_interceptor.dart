import 'dart:math';

import 'package:dio/dio.dart';

/// Puts an `Idempotency-Key` header on every POST, PUT, PATCH and DELETE, so a
/// server that keeps the key can tell a replay from a second action
/// (team_app #50, student_app #1).
///
/// One key per user action:
///  * A form that can be sent more than once for the same action (the person
///    taps Retry after a failure) makes one key with [newKey] and passes it on
///    every attempt: `Options(extra: {IdempotencyInterceptor.extraKey: key})`.
///    Every attempt then carries that key, and a new form makes a new one.
///  * Without a form key, a key is made here once per request and kept in
///    [RequestOptions.extra]. [RetryInterceptor] and the auth interceptors
///    replay the same [RequestOptions], so a replay sends the same key.
///
/// A key the caller already set as a header is kept. Reads (GET, HEAD,
/// OPTIONS) carry no key.
///
/// Keys are random version 4 UUIDs from [Random.secure]. That is the form the
/// Scheduler checks where it reads the header today
/// (controllers/email/campaignsController.js, `idempotencyKeyOf`).
class IdempotencyInterceptor extends Interceptor {
  IdempotencyInterceptor({Random? random}) : _random = random ?? _secure;

  final Random _random;

  /// The header the key travels in.
  static const header = 'Idempotency-Key';

  /// The [RequestOptions.extra] entry that holds the action's key.
  static const extraKey = 'idempotencyKey';

  static const _mutating = {'POST', 'PUT', 'PATCH', 'DELETE'};

  static final Random _secure = Random.secure();

  /// A new key for one user action (one form, one button press).
  static String newKey() => _uuidV4(_secure);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_mutating.contains(options.method.toUpperCase())) {
      options.headers[header] = _keyFor(options);
    }
    handler.next(options);
  }

  String _keyFor(RequestOptions options) {
    final fromForm = options.extra[extraKey];
    if (fromForm is String && fromForm.isNotEmpty) return fromForm;
    final fromHeader = options.headers[header];
    final key = fromHeader is String && fromHeader.isNotEmpty
        ? fromHeader
        : _uuidV4(_random);
    options.extra[extraKey] = key;
    return key;
  }

  static String _uuidV4(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
