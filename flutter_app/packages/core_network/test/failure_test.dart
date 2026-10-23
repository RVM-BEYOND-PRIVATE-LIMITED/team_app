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
}
