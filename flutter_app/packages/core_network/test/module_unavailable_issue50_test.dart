import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// team_app #50 item 12, the module-off part: a module route's 404
/// `NOT_FOUND` (a closed feature switch, Scheduler_Backend
/// middleware/requireFeature.js) is a [ModuleUnavailableFailure]; a 404 on any
/// other request stays a plain [NotFoundFailure].

/// What a closed switch answers (requireFeature.js), and what an unknown path
/// answers (server.js), e.g. a module that is not on this server yet.
const _switchClosed = {'error': 'Not found', 'code': 'NOT_FOUND'};
const _unknownPath = {'error': 'API endpoint not found.', 'code': 'NOT_FOUND'};

Dio _client(ResponseBody Function(RequestOptions o) answer) =>
    Dio(BaseOptions(baseUrl: 'https://scheduler.test/api'))
      ..httpClientAdapter = ScriptedAdapter(answer)
      ..interceptors.add(const ErrorMappingInterceptor());

Future<Failure> _failureOf(Dio dio, String path, {Options? options}) async {
  try {
    await dio.get<Object?>(path, options: options);
  } on DioException catch (e) {
    return e.asFailure;
  }
  fail('expected $path to fail');
}

void main() {
  group('ModuleRequest', () {
    test('names the module of a tagged request, and nothing else', () {
      expect(
          ModuleRequest.of(RequestOptions(extra: ModuleRequest.extra('crm'))),
          'crm');
      expect(ModuleRequest.of(RequestOptions()), isNull);
      expect(
          ModuleRequest.of(RequestOptions(extra: {ModuleRequest.extraKey: ''})),
          isNull);
      expect(
          ModuleRequest.of(RequestOptions(extra: {ModuleRequest.extraKey: 7})),
          isNull);
    });
  });

  group('Failure.forModule', () {
    test('a module request\'s 404 NOT_FOUND is module unavailable', () {
      final failure = Failure.forModule(
          const NotFoundFailure('Not found', 'NOT_FOUND', 'req-1'), 'crm');

      expect(failure, isA<ModuleUnavailableFailure>());
      failure as ModuleUnavailableFailure;
      expect(failure.module, 'crm');
      expect(failure.statusCode, 404);
      expect(failure.code, 'NOT_FOUND');
      expect(failure.requestId, 'req-1');
      expect(failure.message, ModuleUnavailableFailure.defaultMessage);
      // Still a NotFoundFailure for code that only knows "not found".
      expect(failure, isA<NotFoundFailure>());
    });

    test('anything else is unchanged', () {
      const plain = NotFoundFailure('Not found', 'NOT_FOUND');
      expect(Failure.forModule(plain, null), same(plain));

      for (final failure in <Failure>[
        const NotFoundFailure('Lead not found.', 'LEAD_NOT_FOUND'),
        const NotFoundFailure(),
        const ForbiddenFailure('Access denied.', 'NOT_FOUND'),
        ServerFailure.status(500, code: 'NOT_FOUND'),
        const UnauthorizedFailure(code: 'TOKEN_EXPIRED'),
        const TimeoutFailure(),
      ]) {
        expect(Failure.forModule(failure, 'crm'), same(failure),
            reason: '$failure');
      }
    });

    test('equality keeps the module apart', () {
      expect(const ModuleUnavailableFailure('crm'),
          const ModuleUnavailableFailure('crm'));
      expect(const ModuleUnavailableFailure('crm'),
          isNot(const ModuleUnavailableFailure('fees')));
    });
  });

  group('through the client', () {
    for (final body in [_switchClosed, _unknownPath]) {
      test('a tagged request answered ${body['error']} is module off',
          () async {
        final dio = _client((_) => jsonReply(404, body));
        final failure = await _failureOf(dio, '/crm/leads',
            options: Options(extra: ModuleRequest.extra('crm')));
        expect(failure, const ModuleUnavailableFailure('crm'));
      });

      test('an untagged request answered ${body['error']} is as before',
          () async {
        final dio = _client((_) => jsonReply(404, body));
        final failure = await _failureOf(dio, '/students/9');
        expect(failure, isNot(isA<ModuleUnavailableFailure>()));
        expect(failure, NotFoundFailure(body['error'], 'NOT_FOUND'));
      });
    }

    test('a tagged request\'s other refusals are as before', () async {
      final dio = _client((_) => jsonReply(403, {'error': 'Access denied.'}));
      final failure = await _failureOf(dio, '/crm/leads',
          options: Options(extra: ModuleRequest.extra('crm')));
      expect(failure, const ForbiddenFailure('Access denied.'));
    });
  });
}
