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

/// team_app #50 item 12, the rate-limit part: any 429 is a
/// [TooManyRequestsFailure], and the shared BlockedState shows it as "wait and
/// try again". The Scheduler answers 429 `{ error, code: 'RATE_LIMITED' }`
/// (Scheduler_Backend middleware/punchCodeLimiter.js) and
/// `{ error, code: 'INTAKE_RATE_LIMITED' }` (controllers/intakeController.js);
/// the ESS answers 429 `RATE_LIMITED` (apps/ess-api src/middleware/rateLimit.js).

const _punchLimit = {
  'error': 'Too many sign-in attempts from this network. '
      'Wait fifteen minutes and try again.',
  'code': 'RATE_LIMITED',
};

const _intakeLimit = {
  'error': 'Too many attempts. Wait fifteen minutes and try again.',
  'code': 'INTAKE_RATE_LIMITED',
};

/// A longer wait: the intake's per-number limit (controllers/intakeController.js).
const _intakeAttempts = {
  'error': 'Too many attempts for this mobile number. Try again in an hour, '
      'or contact the admissions office.',
  'code': 'INTAKE_ATTEMPTS',
};

void main() {
  group('a 429 is the rate-limit blocked state (item 12)', () {
    test('any TooManyRequestsFailure, whatever its code', () {
      for (final failure in <Failure>[
        const TooManyRequestsFailure(),
        const TooManyRequestsFailure(null, null, 'RATE_LIMITED'),
        Failure.fromStatus(
            429, _punchLimit['error'], _punchLimit['code'], 'req-1'),
        Failure.fromStatus(429, _intakeLimit['error'], _intakeLimit['code']),
        // Lock-outs and code limits are 429s too: wait, then try again.
        Failure.fromStatus(429, 'Too many wrong passwords.', 'LOCKED'),
        Failure.fromStatus(429, 'Too many codes.', 'TOO_MANY_CODES'),
        Failure.fromStatus(429),
      ]) {
        expect(failure, isA<TooManyRequestsFailure>(), reason: '$failure');
        expect(blockedReasonFor(failure), BlockedReason.rateLimited,
            reason: '$failure');
      }
    });

    test('module off is unchanged, and other failures stay errors', () {
      expect(blockedReasonFor(const ModuleUnavailableFailure('crm')),
          BlockedReason.moduleOff);
      for (final failure in <Object?>[
        const NotFoundFailure('Not found', 'NOT_FOUND'),
        const ForbiddenFailure(),
        const UnauthorizedFailure(),
        const ServerFailure(),
        const ServerFailure.status(503, code: 'RATE_LIMITED'),
        const BadResponseFailure('Refused.',
            statusCode: 400, code: 'RATE_LIMITED'),
        const TimeoutFailure(),
        const NoConnectionFailure(),
        'RATE_LIMITED',
        null,
      ]) {
        expect(blockedReasonFor(failure), isNull, reason: '$failure');
      }
    });

    group('through the app\'s Scheduler client', () {
      Dio client(int status, Object body) => Dio(
            BaseOptions(baseUrl: 'https://scheduler.test/api'),
          )
            ..httpClientAdapter = _Reply(status, body)
            ..interceptors.add(const ErrorMappingInterceptor())
            // As rvm_team_app lib/injection.dart sets it: refusals are values.
            ..options.validateStatus = (s) => s != null && s != 401;

      Future<Object?> failureOf(Future<Object?> request) =>
          request.then<Object?>((_) => null, onError: (Object e) => e);

      test('the punch limiter\'s 429 RATE_LIMITED', () async {
        final source = _Source(client(429, _punchLimit));
        final failure = await failureOf(source.read('/hr/my-attendance/otp'));
        expect(failure, isA<TooManyRequestsFailure>());
        failure as TooManyRequestsFailure;
        expect(failure.code, 'RATE_LIMITED');
        expect(failure.message, _punchLimit['error']);
        expect(blockedReasonFor(failure), BlockedReason.rateLimited);
      });

      test('the intake\'s 429 INTAKE_RATE_LIMITED', () async {
        final source = _Source(client(429, _intakeLimit));
        final failure = await failureOf(source.raw('/intake'));
        expect(failure, isA<TooManyRequestsFailure>());
        expect((failure as Failure).code, 'INTAKE_RATE_LIMITED');
        expect(blockedReasonFor(failure), BlockedReason.rateLimited);
      });

      test('the intake\'s hour-long 429 INTAKE_ATTEMPTS keeps its wait',
          () async {
        final source = _Source(client(429, _intakeAttempts));
        final failure = await failureOf(source.raw('/intake'));
        expect(failure, isA<TooManyRequestsFailure>());
        failure as TooManyRequestsFailure;
        expect(failure.code, 'INTAKE_ATTEMPTS');
        expect(failure.message, _intakeAttempts['error']);
        expect(failure.message, contains('an hour'));
        expect(blockedReasonFor(failure), BlockedReason.rateLimited);
      });

      test('a module request\'s 429 is a rate limit, not module off',
          () async {
        final source = _Source(client(429, _punchLimit));
        final failure =
            await failureOf(source.read('/crm/leads', TeamModule.crm));
        expect(failure, isA<TooManyRequestsFailure>());
        expect(failure, isNot(isA<ModuleUnavailableFailure>()));
        expect(blockedReasonFor(failure), BlockedReason.rateLimited);
      });
    });
  });

  group('the rate-limit BlockedState', () {
    Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
          theme: theme ?? RvmTheme.light(seed: RvmColors.clay),
          home: child,
        );

    testWidgets('a calm title, a wait-and-try-again message and an icon',
        (tester) async {
      const reason = BlockedReason.rateLimited;
      expect(reason.title, isNotEmpty);
      expect(reason.message, contains('Wait'));
      expect(reason.message, contains('try again'));
      expect(reason.title, isNot(contains('!')));
      expect(reason.message, isNot(contains('!')));
      // Waits differ (fifteen minutes, an hour, a lock-out's own time), so
      // the default names no length of wait: only the server's message does.
      for (final length in ['second', 'minute', 'hour', 'day', 'few']) {
        expect(reason.message.toLowerCase(), isNot(contains(length)),
            reason: reason.message);
      }
      expect(reason.message, isNot(matches(RegExp(r'\d'))));

      await tester.pumpWidget(host(const BlockedState(reason: reason)));
      expect(find.byIcon(reason.icon), findsOneWidget);
      expect(find.text(reason.title), findsOneWidget);
      expect(find.text(reason.message), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows the server\'s own wait, with one 44 px action',
        (tester) async {
      var taps = 0;
      final failure = Failure.fromStatus(
          429, _punchLimit['error'], _punchLimit['code']);
      await tester.pumpWidget(host(BlockedState(
        reason: blockedReasonFor(failure)!,
        message: failure.message,
        actionLabel: 'Try again',
        onAction: () => taps++,
      )));
      expect(find.text(BlockedReason.rateLimited.title), findsOneWidget);
      expect(find.text(_punchLimit['error']!), findsOneWidget);
      expect(find.text(BlockedReason.rateLimited.message), findsNothing);

      final button = find.ancestor(
          of: find.text('Try again'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text('Try again'));
      expect(taps, 1);
    });

    testWidgets('a longer wait from the server is shown, not the default',
        (tester) async {
      for (final failure in [
        Failure.fromStatus(
            429, _intakeAttempts['error'], _intakeAttempts['code']),
        Failure.fromStatus(
            429,
            'Too many wrong passwords. Try again in 30 minutes, '
            'or use "Get a code".',
            'LOCKED'),
      ]) {
        await tester.pumpWidget(host(BlockedState(
          key: ValueKey(failure.code),
          reason: blockedReasonFor(failure)!,
          message: failure.message,
        )));
        expect(find.text(failure.message), findsOneWidget,
            reason: failure.message);
        expect(find.text(BlockedReason.rateLimited.message), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    for (final size in const [
      Size(320, 480),
      Size(360, 640),
      Size(480, 320),
      Size(390, 844),
      Size(1024, 768),
    ]) {
      for (final scale in const [1.0, 2.0, 3.0]) {
        for (final dark in const [false, true]) {
          testWidgets(
              'fits ${size.width.toInt()}x${size.height.toInt()} at text '
              'x$scale${dark ? ', dark' : ''}', (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            var taps = 0;
            await tester.pumpWidget(host(
              BlockedState(
                reason: BlockedReason.rateLimited,
                message: _punchLimit['error'],
                actionLabel: 'Try again',
                onAction: () => taps++,
              ),
              theme: dark
                  ? RvmTheme.dark(seed: RvmColors.clay)
                  : RvmTheme.light(seed: RvmColors.clay),
            ));

            expect(tester.takeException(), isNull);
            expect(find.byType(Scrollable), findsOneWidget);
            expect(
                MediaQuery.textScalerOf(
                        tester.element(find.text('Try again')))
                    .scale(10),
                10 * scale);

            // The action can always be reached and tapped, at 44 px or more.
            await tester.ensureVisible(find.text('Try again'));
            await tester.pumpAndSettle();
            final button = find.ancestor(
                of: find.text('Try again'),
                matching:
                    find.byWidgetPredicate((w) => w is ButtonStyleButton));
            expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
            expect(tester.getSize(button).width, lessThanOrEqualTo(size.width));
            await tester.tap(find.text('Try again'));
            expect(taps, 1);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
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
