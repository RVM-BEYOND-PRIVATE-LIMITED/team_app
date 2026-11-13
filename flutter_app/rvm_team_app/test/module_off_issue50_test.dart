import 'dart:convert';
import 'dart:typed_data';

import 'package:core_network/core_network.dart';
import 'package:core_ui/core_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/data/dio_executor.dart';
import 'package:rvm_team_app/data/module_request.dart';
import 'package:rvm_team_app/router/module_routes.dart';
import 'package:rvm_team_app/widgets/blocked_state.dart';

/// team_app #50 item 12, the module-off part: a module's own request that the
/// Scheduler answers 404 `NOT_FOUND` (a closed feature switch,
/// Scheduler_Backend middleware/requireFeature.js) is "module off" in the
/// shared BlockedState. A 404 `NOT_FOUND` on any other request is unchanged.

void main() {
  group('a closed module shows "module off" (item 12)', () {
    test('only a module request\'s 404 NOT_FOUND is module off', () {
      expect(blockedReasonFor(const ModuleUnavailableFailure('crm')),
          BlockedReason.moduleOff);
      // A 429 is no longer an error to show: it is the rate-limit blocked
      // state (test/rate_limited_issue50_test.dart), never "module off".
      expect(blockedReasonFor(const TooManyRequestsFailure()),
          isNot(BlockedReason.moduleOff));
      for (final failure in <Object?>[
        const NotFoundFailure('Not found', 'NOT_FOUND'),
        const ForbiddenFailure(),
        const ServerFailure(),
        const UnauthorizedFailure(),
        null,
      ]) {
        expect(blockedReasonFor(failure), isNull, reason: '$failure');
      }
    });

    testWidgets('the shared BlockedState shows it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: RvmTheme.light(seed: RvmColors.clay),
        home: BlockedState(
            reason: blockedReasonFor(const ModuleUnavailableFailure('crm'))!),
      ));
      expect(find.text(BlockedReason.moduleOff.title), findsOneWidget);
      expect(find.text(BlockedReason.moduleOff.message), findsOneWidget);
      expect(find.byIcon(BlockedReason.moduleOff.icon), findsOneWidget);
    });

    group('through the app\'s Scheduler client', () {
      Dio client(int status, Object body) => Dio(
            BaseOptions(baseUrl: 'https://scheduler.test/api'),
          )
            ..httpClientAdapter = _Reply(status, body)
            ..interceptors.add(const ErrorMappingInterceptor())
            // As rvm_team_app lib/injection.dart sets it: refusals are values.
            ..options.validateStatus = (s) => s != null && s != 401;

      const switchClosed = {'error': 'Not found', 'code': 'NOT_FOUND'};

      test('a module request answered 404 NOT_FOUND is module off', () async {
        final source = _Source(client(404, switchClosed));
        await expectLater(source.read('/crm/leads', TeamModule.crm),
            throwsA(const ModuleUnavailableFailure('crm')));
        await expectLater(source.raw('/crm/leads', TeamModule.crm),
            throwsA(const ModuleUnavailableFailure('crm')));
      });

      test('the same 404 on any other request is as before', () async {
        final source = _Source(client(404, switchClosed));
        final failure = await source
            .read('/students/9')
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(failure, const NotFoundFailure('Not found', 'NOT_FOUND'));
        expect(failure, isNot(isA<ModuleUnavailableFailure>()));
        expect(blockedReasonFor(failure), isNull);
      });

      test('a module request\'s other refusals are as before', () async {
        final source =
            _Source(client(404, {'error': 'Lead not found.', 'code': 'X'}));
        await expectLater(source.read('/crm/leads/7', TeamModule.crm),
            throwsA(const NotFoundFailure('Lead not found.', 'X')));
      });
    });
  });
}

/// A data source as a module would write one.
class _Source with DioExecutor {
  _Source(this._dio);
  final Dio _dio;

  /// Parses inside guard: the status is checked by [bodyOf].
  Future<Object?> read(String path, [TeamModule? module]) => guard(() async =>
      bodyOf(await _dio.get<Object?>(path, options: module?.requestOptions)));

  /// Returns the response: the status is checked by guard itself.
  Future<Response<Object?>> raw(String path, [TeamModule? module]) =>
      guard(() => _dio.get<Object?>(path, options: module?.requestOptions));
}

class _Reply implements HttpClientAdapter {
  _Reply(this.status, this.body);
  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(json.encode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}
