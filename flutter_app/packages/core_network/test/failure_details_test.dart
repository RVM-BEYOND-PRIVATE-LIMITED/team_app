import 'dart:async';

import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// student_app #1, item 7: the error shape `{code, message, details,
/// request_id}`. A failure keeps the body's top-level `details` exactly as
/// decoded, wherever it keeps `request_id`, and never prints it: it may hold
/// personal data. Its inner shape is student_app #10's to define.

DioException _refusal(int status, Object? data,
        {Map<String, dynamic>? extra}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x', extra: extra),
      type: DioExceptionType.badResponse,
      response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: status,
          data: data),
    );

/// Test-only values a `details` could carry: a number, a name, a marker.
const _number = '9999999999';
const _name = 'Test Student';
const _marker = 'details-marker';

Map<String, Object?> _personal() => {
      'fields': {'phone': _number, 'name': _name},
      'note': _marker,
    };

/// Each `details` shape the body may carry: a map, a list or a scalar.
List<Object> _shapes() => [
      _personal(),
      [
        {'field': 'phone', 'value': _number},
        _marker,
      ],
      'Check the form ($_marker).',
      3,
      true,
    ];

const _statuses = [400, 401, 403, 404, 409, 422, 429, 500, 502, 503];

void main() {
  group('Failure.details', () {
    test('carries a map, a list or a scalar exactly as decoded', () {
      for (final status in _statuses) {
        for (final details in _shapes()) {
          final f = Failure.fromDio(_refusal(status, {
            'code': 'SOME_CODE',
            'message': 'Refused.',
            'details': details,
            'request_id': 'req-test-1',
          }));
          expect(f.details, same(details), reason: '$status $details');
          expect(f.requestId, 'req-test-1', reason: '$status');
          expect(f.statusCode, status, reason: '$status');
        }
      }
    });

    test('goes wherever request_id goes', () {
      final details = _personal();
      for (final status in [401, 403, 404, 422, 429, 500, 503]) {
        final f = Failure.fromStatus(status, 'Refused.', 'X', 'req-1', details);
        expect(f.details, same(details), reason: '$status');
        expect(f.requestId, 'req-1', reason: '$status');
      }
      for (final f in <Failure>[
        UnauthorizedFailure(details: details),
        ForbiddenFailure(null, null, null, details),
        NotFoundFailure(null, null, null, details),
        ModuleUnavailableFailure('crm', details: details),
        TooManyRequestsFailure(null, null, null, details),
        ServerFailure.status(500, details: details),
        BadResponseFailure('Refused.', statusCode: 400, details: details),
      ]) {
        expect(f.details, same(details), reason: '${f.runtimeType}');
      }
      // A failure that carries no request id carries no details either.
      expect(Failure.fromStatus(408, 'Slow.', 'X', 'req-1', details),
          const TimeoutFailure());
    });

    test('a module request keeps it when it becomes module unavailable', () {
      final details = _personal();
      final f = Failure.fromDio(_refusal(
          404, {'error': 'Not found', 'code': 'NOT_FOUND', 'details': details},
          extra: ModuleRequest.extra('crm')));
      expect(f, isA<ModuleUnavailableFailure>());
      expect(f.details, same(details));
    });

    test('is null when the body has none, and the failure is as before', () {
      final none = Failure.fromDio(_refusal(
          400, {'error': 'That code is not right.', 'code': 'WRONG_CODE'}));
      expect(none.details, isNull);
      expect(
          none,
          const BadResponseFailure('That code is not right.',
              statusCode: 400, code: 'WRONG_CODE'));

      final explicitNull = Failure.fromDio(
          _refusal(404, {'error': 'Gone.', 'details': null}));
      expect(explicitNull.details, isNull);
      expect(explicitNull, const NotFoundFailure('Gone.'));

      expect(Failure.fromDio(_refusal(429, null)),
          const TooManyRequestsFailure());
    });

    test('a body that is not a JSON object is unchanged', () {
      expect(Failure.fromDio(_refusal(502, '<html>502 Bad Gateway</html>')),
          const ServerFailure.status(502));
      expect(Failure.fromDio(_refusal(404, 'Not found')),
          const NotFoundFailure());
      expect(Failure.fromDio(_refusal(400, ['details', _marker])),
          const BadResponseFailure('Request could not be completed.',
              statusCode: 400));
      for (final data in <Object?>['details', 7, null]) {
        expect(Failure.fromDio(_refusal(409, data)).details, isNull,
            reason: '$data');
      }
    });

    test('a plain-text reply through the client is unchanged', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
        ..httpClientAdapter = ScriptedAdapter((_) => ResponseBody.fromString(
            'Service Unavailable', 503,
            headers: {
              Headers.contentTypeHeader: ['text/plain'],
            }))
        ..interceptors.add(const ErrorMappingInterceptor());
      try {
        await dio.get<Object?>('/x');
        fail('expected a refusal');
      } on DioException catch (e) {
        expect(e.asFailure, const ServerFailure.status(503));
        expect(e.asFailure.details, isNull);
      }
    });

    test('is part of equality, compared by value', () {
      const base = NotFoundFailure('Gone.', 'X', 'req-a');
      final a = NotFoundFailure('Gone.', 'X', 'req-a', _personal());
      final b = NotFoundFailure('Gone.', 'X', 'req-a', _personal());
      final other = NotFoundFailure('Gone.', 'X', 'req-a', {'note': 'other'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(other));
      expect(a, isNot(base));
      // Without details a failure equals the one built before details existed.
      expect(const NotFoundFailure('Gone.', 'X', 'req-a', null), base);
    });

    test('never appears in the text', () {
      final withDetails = <Failure>[
        for (final status in _statuses)
          for (final details in _shapes())
            Failure.fromDio(_refusal(status, {
              'code': 'SOME_CODE',
              'error': 'Refused.',
              'details': details,
              'request_id': 'req-test-1',
            })),
        UnauthorizedFailure(details: _personal()),
        ForbiddenFailure(null, null, null, _personal()),
        NotFoundFailure(null, null, null, _personal()),
        ModuleUnavailableFailure('crm', details: _personal()),
        TooManyRequestsFailure(null, null, null, _personal()),
        ServerFailure.status(500, details: _personal()),
        BadResponseFailure('Refused.', details: _personal()),
      ];
      for (final f in withDetails) {
        expect(f.details, isNotNull);
        final text = f.toString();
        for (final secret in [_number, _name, _marker, 'details', 'fields']) {
          expect(text, isNot(contains(secret)), reason: text);
        }
      }
      // The text is exactly what it was before details existed.
      expect(NotFoundFailure('Gone.', 'X', 'req-a', _personal()).toString(),
          const NotFoundFailure('Gone.', 'X', 'req-a').toString());
    });

    test('never reaches a log line or the error the client throws', () async {
      final lines = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
        ..httpClientAdapter = ScriptedAdapter((_) => jsonReply(422, {
              'error': 'Check the form.',
              'code': 'VALIDATION',
              'details': _personal(),
              'request_id': 'req-9',
            }))
        ..interceptors.addAll([
          LoggingInterceptor(),
          const ErrorMappingInterceptor(),
        ]);

      late DioException thrown;
      await runZoned(() async {
        try {
          await dio.post<Object?>('/x', data: const {'a': 1});
          fail('expected a refusal');
        } on DioException catch (e) {
          thrown = e;
        }
      },
          zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => lines.add(line)));

      final failure = thrown.asFailure;
      expect(failure.details, _personal());
      expect(failure.requestId, 'req-9');
      expect(lines, isNotEmpty);
      for (final text in [...lines, '$thrown', '$failure']) {
        for (final secret in [_number, _name, _marker]) {
          expect(text, isNot(contains(secret)), reason: text);
        }
      }
    });
  });
}
