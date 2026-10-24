import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/data/datasources/work_remote_data_source.dart';

/// Regression tests for issues_image/issue15: signed in as ADMIN, Me ->
/// Interviews crashed because `GET /api/interviews` answers 403
/// (`INTERVIEWS_ACCESS_DENIED`) to callers who are neither a blanket role nor
/// on a panel. The list endpoint now treats that refusal as an empty calendar
/// — the same answer the sibling `mine/upcoming` endpoint gives — so the tab
/// cannot crash for any role in any condition.
Dio _refusingDio({required int status, Object? body}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: status,
            data: body,
          ),
        ),
        true,
      ),
    ),
  );
  return dio;
}

void main() {
  test('403 INTERVIEWS_ACCESS_DENIED becomes an empty calendar', () async {
    final source = WorkRemoteDataSource(_refusingDio(
      status: 403,
      body: const {
        'error': 'Only the interview panel can open this: HR, the CEO, '
            'a Super Admin, the Head of Operations, or somebody who is '
            'taking interviews.',
        'code': 'INTERVIEWS_ACCESS_DENIED',
      },
    ));

    expect(await source.interviews(), isEmpty);
  });

  test('a genuine 500 still throws instead of hiding', () async {
    final source = WorkRemoteDataSource(_refusingDio(
      status: 500,
      body: const {'error': 'boom'},
    ));

    expect(source.interviews(), throwsA(isA<ServerFailure>()));
  });

  test('a 200 with no rounds parses to empty', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: const {'interviews': []},
          ),
        ),
      ),
    );

    expect(await WorkRemoteDataSource(dio).interviews(), isEmpty);
  });
}
