import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// Typed failure surfaced to repositories → blocs → UI. Every variant carries a
/// [message] that states the REAL cause, so centered error states never fall
/// back to a generic "something went wrong" when the cause is known.
sealed class Failure extends Equatable implements Exception {
  const Failure(this.message, {this.statusCode, this.code, this.requestId});

  final String message;
  final int? statusCode;
  final String? code;

  /// The server's id for the refused request, from the error body's
  /// `request_id`, so an error screen can show it for support (the error shape
  /// student_app #1 names). Null when the reply carries none, which today is
  /// every Team RVM and Scheduler reply.
  final String? requestId;

  @override
  List<Object?> get props => [message, statusCode, code, requestId];

  @override
  String toString() =>
      '$runtimeType($statusCode${code == null ? '' : ' $code'}): $message'
      '${requestId == null ? '' : ' [request $requestId]'}';

  /// Map a raw dio error into the right typed failure. Reachability (real
  /// offline) is best detected up-front by the connectivity service, but a
  /// connection error here still maps to [NoConnectionFailure].
  factory Failure.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NoConnectionFailure();
      case DioExceptionType.badCertificate:
        return const ServerFailure(
            'Secure connection failed, please try again.');
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled.');
      case DioExceptionType.unknown:
        // dio wraps SocketException (no route to host) as unknown.
        if (e.error.toString().contains('SocketException'))
          return const NoConnectionFailure();
        return const UnknownFailure();
      case DioExceptionType.badResponse:
        final data = e.response?.data;
        return Failure.fromStatus(e.response?.statusCode, _extract(data),
            _extractCode(data), _extractRequestId(data));
    }
  }

  /// Map an HTTP status to a typed failure, preferring a server-supplied message.
  /// [serverCode] is the backend's machine-readable `code` (e.g. Scheduler
  /// `TWO_FACTOR_UNAVAILABLE`, `WRONG_CODE`) — kept so a caller can pick
  /// app-owned copy; 5xx text itself stays generic (it may name internals).
  /// [requestId] is the reply's `request_id`, when it sends one.
  factory Failure.fromStatus(int? status,
      [String? serverMessage, String? serverCode, String? requestId]) {
    if (status == null) return const UnknownFailure();
    return switch (status) {
      401 => _unauthorized(serverMessage, serverCode, requestId),
      403 => ForbiddenFailure(serverMessage, serverCode, requestId),
      404 => NotFoundFailure(serverMessage, serverCode, requestId),
      408 => const TimeoutFailure(),
      // The limiter's message states the real wait (e.g. "…in 15 minutes").
      // Its code stays too (`RATE_LIMITED`, `LOCKED`, `TOO_MANY_CODES`…), so a
      // screen can tell a limit from a lock-out (team_app #50, item 12).
      429 => TooManyRequestsFailure(serverMessage, requestId, serverCode),
      // The ESS's 503s (MODULE_NOT_INSTALLED / MODULE_DISABLED / UNAVAILABLE)
      // carry copy written for staff, so those keep their message; other 5xx
      // text stays generic (it may name internals).
      503
          when serverCode == 'MODULE_NOT_INSTALLED' ||
              serverCode == 'MODULE_DISABLED' ||
              serverCode == 'UNAVAILABLE' =>
        ServerFailure.status(status,
            code: serverCode, message: serverMessage, requestId: requestId),
      _ when status >= 500 =>
        ServerFailure.status(status, code: serverCode, requestId: requestId),
      _ when status >= 400 => BadResponseFailure(
          serverMessage ?? 'Request could not be completed.',
          statusCode: status,
          code: serverCode,
          requestId: requestId),
      _ => const UnknownFailure(),
    };
  }

  /// The two bodies the Scheduler's auth guards send when they reject a token.
  /// Every other 401 is about what the request said (e.g. "Wrong password." on
  /// `/api/me/phone/request`), so its own wording is the useful message. Calling
  /// that "Session expired" hides the real cause and sends people to sign in
  /// again for no reason.
  static const _tokenRejections = {'No token provided', 'Please authenticate'};

  static Failure _unauthorized(
      String? serverMessage, String? serverCode, String? requestId) {
    final message = serverMessage?.trim();
    if (message != null &&
        message.isNotEmpty &&
        !_tokenRejections.contains(message)) {
      return UnauthorizedFailure(
          message: message, code: serverCode, requestId: requestId);
    }
    return UnauthorizedFailure(code: serverCode, requestId: requestId);
  }

  /// Pull `{error:{message}}` (JobPortal) or `{message|error}` (Scheduler).
  static String? _extract(dynamic data) {
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null)
        return err['message'].toString();
      final m = data['message'] ?? data['error'];
      if (m != null) return m.toString();
    }
    return null;
  }

  /// Pull `{error:{code}}` (JobPortal) or `{code}` (Scheduler).
  static String? _extractCode(dynamic data) {
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['code'] != null) return err['code'].toString();
      if (data['code'] != null) return data['code'].toString();
    }
    return null;
  }

  /// Pull `{request_id}`, the field of the error shape student_app #1 names.
  /// No Team RVM or Scheduler reply sends it today, so this stays null there.
  static String? _extractRequestId(dynamic data) {
    if (data is! Map) return null;
    final id = data['request_id'];
    if (id is! String && id is! num) return null;
    final text = '$id'.trim();
    return text.isEmpty ? null : text;
  }
}

class NoConnectionFailure extends Failure {
  const NoConnectionFailure() : super('No internet connection');
}

class TimeoutFailure extends Failure {
  const TimeoutFailure() : super('Request timed out. Please try again.');
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({String? message, String? code, String? requestId})
      : super(message ?? 'Session expired, please log in again.',
            statusCode: 401, code: code, requestId: requestId);
}

class ForbiddenFailure extends Failure {
  // Prefer the server's message (RVM 403s carry actionable text, e.g. "Cannot
  // reply to a resolved ticket. Please reopen it first."); fall back generic.
  const ForbiddenFailure([String? message, String? code, String? requestId])
      : super(message ?? "You don't have access to this.",
            statusCode: 403, code: code, requestId: requestId);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([String? message, String? code, String? requestId])
      : super(message ?? 'No data found.',
            statusCode: 404, code: code, requestId: requestId);
}

class TooManyRequestsFailure extends Failure {
  const TooManyRequestsFailure(
      [String? message, String? requestId, String? code])
      : super(
            message ?? 'Too many attempts. Please try again in a few minutes.',
            statusCode: 429,
            code: code,
            requestId: requestId);
}

class ServerFailure extends Failure {
  const ServerFailure([String? message])
      : super(message ?? _generic, statusCode: 500);

  /// A real 5xx response: keeps its status + the backend's machine `code`.
  /// [message] is only passed for 5xx bodies written for staff to read.
  const ServerFailure.status(int statusCode,
      {String? code, String? message, String? requestId})
      : super(message ?? _generic,
            statusCode: statusCode, code: code, requestId: requestId);

  static const _generic = 'Server error, please try again.';
}

class BadResponseFailure extends Failure {
  const BadResponseFailure(super.message,
      {super.statusCode, super.code, super.requestId});
}

class ParseFailure extends Failure {
  const ParseFailure() : super("Couldn't read the server response.");
}

class UnknownFailure extends Failure {
  const UnknownFailure([String? message])
      : super(message ?? 'Something went wrong. Please try again.');
}
