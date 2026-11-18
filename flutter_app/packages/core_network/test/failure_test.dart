import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

DioException _dio(DioExceptionType type, {int? status, dynamic data}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      response: status == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: status,
              data: data),
    );

void main() {
  group('Failure.fromDio', () {
    test('connection timeout → TimeoutFailure', () {
      expect(Failure.fromDio(_dio(DioExceptionType.connectionTimeout)),
          isA<TimeoutFailure>());
    });

    test('connection error → NoConnectionFailure with real-cause message', () {
      final f = Failure.fromDio(_dio(DioExceptionType.connectionError));
      expect(f, isA<NoConnectionFailure>());
      expect(f.message, 'No internet connection');
    });

    test('401 → UnauthorizedFailure ("Session expired")', () {
      final f =
          Failure.fromDio(_dio(DioExceptionType.badResponse, status: 401));
      expect(f, isA<UnauthorizedFailure>());
      expect(f.message, contains('Session expired'));
    });

    test('401 with a token rejection → the session-expired copy', () {
      for (final body in ['Please authenticate', 'No token provided']) {
        final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
            status: 401, data: {'error': body}));
        expect(f, isA<UnauthorizedFailure>());
        expect(f.message, contains('Session expired'));
      }
    });

    test('401 from a password check keeps the real server message', () {
      final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
          status: 401, data: {'error': 'Wrong password.'}));
      expect(f, isA<UnauthorizedFailure>());
      expect(f.message, 'Wrong password.');
    });

    test('404 → NotFoundFailure, prefers server message', () {
      final f = Failure.fromDio(
          _dio(DioExceptionType.badResponse, status: 404, data: {
        'error': {'message': 'No such job'}
      }));
      expect(f, isA<NotFoundFailure>());
      expect(f.message, 'No such job');
    });

    test('403 → ForbiddenFailure, surfaces the server message verbatim', () {
      final f = Failure.fromDio(
          _dio(DioExceptionType.badResponse, status: 403, data: {
        'error': 'Cannot reply to a resolved ticket. Please reopen it first.'
      }));
      expect(f, isA<ForbiddenFailure>());
      expect(f.message,
          'Cannot reply to a resolved ticket. Please reopen it first.');
    });

    test('403 with no body → generic access message', () {
      final f =
          Failure.fromDio(_dio(DioExceptionType.badResponse, status: 403));
      expect(f, isA<ForbiddenFailure>());
      expect(f.message, contains('access'));
    });

    test('500 → ServerFailure', () {
      final f =
          Failure.fromDio(_dio(DioExceptionType.badResponse, status: 500));
      expect(f, isA<ServerFailure>());
      expect(f.message, contains('Server error'));
    });

    test('unknown SocketException → NoConnectionFailure', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.unknown,
        error: 'SocketException: failed host lookup',
      );
      expect(Failure.fromDio(e), isA<NoConnectionFailure>());
    });

    test(
        '404 with a Scheduler string error → NotFoundFailure with that message',
        () {
      final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
          status: 404, data: {'error': 'Location not found.'}));
      expect(f, isA<NotFoundFailure>());
      expect(f.message, 'Location not found.');
    });

    test('429 with a body → keeps the limiter message (the real wait)', () {
      final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
          status: 429,
          data: {
            'error': 'Too many login attempts. Please try again in 15 minutes.'
          }));
      expect(f, isA<TooManyRequestsFailure>());
      expect(f.message, contains('15 minutes'));
    });

    test('429 with no body → generic wait message', () {
      final f =
          Failure.fromDio(_dio(DioExceptionType.badResponse, status: 429));
      expect(f.message, contains('Too many attempts'));
      expect(f.code, isNull);
    });

    // team_app #50, item 12: the limiter's code stays on the typed failure.
    // Scheduler middleware/punchCodeLimiter.js and apps/ess-api
    // src/middleware/rateLimit.js both answer 429 {error, code: RATE_LIMITED}.
    test('429 keeps the RATE_LIMITED code and its message', () {
      final f = Failure.fromDio(
          _dio(DioExceptionType.badResponse, status: 429, data: {
        'error': 'Too many sign-in attempts from this network. '
            'Wait fifteen minutes and try again.',
        'code': 'RATE_LIMITED',
      }));
      expect(f, isA<TooManyRequestsFailure>());
      expect(f.statusCode, 429);
      expect(f.code, 'RATE_LIMITED');
      expect(f.message, contains('Wait fifteen minutes'));
    });

    test('429 keeps any other limiter code (a lock-out is not a limit)', () {
      // Scheduler controllers/hr/attendanceOtpController.js: 429 LOCKED.
      final f = Failure.fromStatus(429, 'Too many wrong passwords.', 'LOCKED');
      expect(f, isA<TooManyRequestsFailure>());
      expect(f.code, 'LOCKED');
      expect(f.message, 'Too many wrong passwords.');
    });

    test('5xx keeps the real status + machine code but NOT the server text',
        () {
      final f = Failure.fromDio(
          _dio(DioExceptionType.badResponse, status: 503, data: {
        'error': 'could not be sent: SMTP_PASS missing',
        'code': 'TWO_FACTOR_UNAVAILABLE'
      }));
      expect(f, isA<ServerFailure>());
      expect(f.statusCode, 503);
      expect(f.code, 'TWO_FACTOR_UNAVAILABLE');
      expect(f.message, 'Server error, please try again.');
    });

    test('4xx keeps the backend code (Scheduler flat + JobPortal nested)', () {
      final flat = Failure.fromDio(_dio(DioExceptionType.badResponse,
          status: 400,
          data: {'error': 'That code is not right.', 'code': 'WRONG_CODE'}));
      expect(flat.code, 'WRONG_CODE');
      expect(flat.message, 'That code is not right.');
      final nested = Failure.fromDio(
          _dio(DioExceptionType.badResponse, status: 422, data: {
        'error': {'code': 'VALIDATION', 'message': 'Bad input'}
      }));
      expect(nested.code, 'VALIDATION');
      expect(nested.message, 'Bad input');
    });
  });

  group('Failure.requestId', () {
    test('is read from the error body\'s request_id for every refusal', () {
      for (final status in [400, 401, 403, 404, 409, 429, 500, 503]) {
        final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
            status: status,
            data: {
              'code': 'SOME_CODE',
              'message': 'Refused.',
              'details': <String, Object?>{},
              'request_id': 'req-test-1',
            }));
        expect(f.requestId, 'req-test-1', reason: 'status $status');
      }
    });

    test('stays null when the reply has none, as every reply has today', () {
      final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
          status: 400,
          data: {'error': 'That code is not right.', 'code': 'WRONG_CODE'}));
      expect(f.requestId, isNull);
      expect(f, const BadResponseFailure('That code is not right.',
          statusCode: 400, code: 'WRONG_CODE'));
      expect(f.toString(), isNot(contains('request')));
      expect(Failure.fromDio(_dio(DioExceptionType.connectionError)).requestId,
          isNull);
    });

    test('ignores a blank or non-text request_id', () {
      for (final id in ['', '  ', <String, Object?>{}, true]) {
        final f = Failure.fromDio(_dio(DioExceptionType.badResponse,
            status: 404, data: {'error': 'Gone.', 'request_id': id}));
        expect(f.requestId, isNull, reason: '$id');
      }
    });

    test('is part of equality and of the text', () {
      const a = NotFoundFailure('Gone.', null, 'req-a');
      const b = NotFoundFailure('Gone.', null, 'req-b');
      expect(a, isNot(b));
      expect(a.toString(), contains('[request req-a]'));
    });
  });
}
