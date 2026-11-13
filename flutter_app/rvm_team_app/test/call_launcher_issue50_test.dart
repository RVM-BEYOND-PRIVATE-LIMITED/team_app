import 'dart:async';
import 'dart:io';

import 'package:core_auth/core_auth.dart';
import 'package:core_network/core_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/injection.dart';
import 'package:rvm_team_app/platform/call_launcher.dart';

// team_app #50, item 1: the dialer hand-off. Only made-up, repeated-digit
// numbers (D19).
const _number = '+919999999999';
const _digits = '9999999999';

abstract class _Launch {
  Future<bool> call(Uri uri);
}

class _MockLaunch extends Mock implements _Launch {}

abstract class _StartCall {
  Future<String> call();
}

class _MockStartCall extends Mock implements _StartCall {}

/// Runs [body] with `print` and `debugPrint` going to [out].
Future<T> _captured<T>(List<String> out, Future<T> Function() body) async {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => out.add('$message');
  try {
    return await runZoned(
      body,
      zoneSpecification:
          ZoneSpecification(print: (self, parent, zone, line) => out.add(line)),
    );
  } finally {
    debugPrint = original;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockLaunch launch;
  late _MockStartCall startCall;
  late CallLauncher launcher;
  late List<String> printed;

  setUpAll(() => registerFallbackValue(Uri()));

  setUp(() {
    launch = _MockLaunch();
    startCall = _MockStartCall();
    launcher = CallLauncher(launch: launch.call);
    printed = [];
    when(() => launch(any())).thenAnswer((_) async => true);
  });

  Future<CallLaunchResult> dial() =>
      _captured(printed, () => launcher.dial(startCall.call));

  /// Nothing the call produced holds the number: the result, its line, its
  /// text, a kept failure, or anything printed.
  void expectNoNumber(CallLaunchResult result) {
    final texts = [
      result.message,
      '$result',
      if (result case CallStartFailed(:final failure)) ...[
        failure.message,
        '$failure',
        '${failure.requestId}',
      ],
      ...printed,
    ];
    for (final text in texts) {
      expect(text, isNot(contains(_digits)), reason: text);
    }
    expect(printed, isEmpty, reason: 'the call helper prints nothing');
  }

  test('the output capture sees print and debugPrint', () async {
    await _captured(printed, () async {
      debugPrint('one');
      // ignore: avoid_print
      print('two');
    });
    expect(printed, ['one', 'two']);
  });

  group('opens the dialer', () {
    test('with tel: and the number from the start-call request', () async {
      when(() => startCall()).thenAnswer((_) async => _number);

      final result = await dial();

      expect(result, const CallDialerOpened());
      final uri = verify(() => launch(captureAny())).captured.single as Uri;
      expect(uri.scheme, 'tel');
      expect(uri.path, _number);
      expect('$uri', 'tel:$_number');
      verify(() => startCall()).called(1);
      expectNoNumber(result);
    });

    test('for a number without a country code', () async {
      when(() => startCall()).thenAnswer((_) async => _digits);

      final result = await dial();

      expect(result, isA<CallDialerOpened>());
      final uri = verify(() => launch(captureAny())).captured.single as Uri;
      expect('$uri', 'tel:$_digits');
      expectNoNumber(result);
    });

    test('trimming space around the number', () async {
      when(() => startCall()).thenAnswer((_) async => ' $_number\n');

      final result = await dial();

      expect(result, isA<CallDialerOpened>());
      final uri = verify(() => launch(captureAny())).captured.single as Uri;
      expect('$uri', 'tel:$_number');
    });
  });

  group('refuses a number that is not digits with one leading +', () {
    for (final bad in [
      '',
      '   ',
      '+',
      '99999 99999',
      '+91 99999 99999',
      '999-999-9999',
      '(999) 9999999',
      '++919999999999',
      '91+9999999999',
      'tel:9999999999',
      '9999999999;ext=1',
      '9999999999,1',
      '*999#9999999999',
      '9999999999999999', // 16 digits, past E.164's 15
      '٩٩٩٩٩٩٩٩٩٩', // digits, but not ASCII ones
      '9999999999 or call 9999999999',
    ]) {
      test('"$bad"', () async {
        when(() => startCall()).thenAnswer((_) async => bad);

        final result = await dial();

        expect(result, const CallNumberInvalid());
        expect(result, isA<CallLaunchFailure>());
        verifyNever(() => launch(any()));
        expectNoNumber(result);
      });
    }
  });

  group('maps a dialer that does not open', () {
    test('when the launch returns false', () async {
      when(() => startCall()).thenAnswer((_) async => _number);
      when(() => launch(any())).thenAnswer((_) async => false);

      final result = await dial();

      expect(result, const CallDialerUnavailable());
      expect(result, isA<CallLaunchFailure>());
      expect(
          result.message, 'No phone app on this device could open the call.');
      expectNoNumber(result);
    });

    test('when the launch throws an error that names the URL', () async {
      when(() => startCall()).thenAnswer((_) async => _number);
      // What url_launcher_android throws when no app takes the URI.
      when(() => launch(any())).thenThrow(PlatformException(
          code: 'ACTIVITY_NOT_FOUND',
          message: 'No Activity found to handle intent { tel:$_number }'));

      final result = await dial();

      expect(result, const CallDialerUnavailable());
      expectNoNumber(result);
    });

    test('when the launch throws anything else', () async {
      when(() => startCall()).thenAnswer((_) async => _number);
      when(() => launch(any())).thenThrow(StateError('tel:$_number'));

      final result = await dial();

      expect(result, const CallDialerUnavailable());
      expectNoNumber(result);
    });
  });

  group('a failed start-call request', () {
    Future<CallLaunchResult> dialThrowing(Object error) {
      when(() => startCall()).thenAnswer((_) => Future.error(error));
      return dial();
    }

    test('keeps a typed failure as it is', () async {
      const offline = NoConnectionFailure();
      final result = await dialThrowing(offline);

      expect(result, const CallStartFailed(offline));
      expect(result, isA<CallLaunchFailure>());
      expect(result.message, 'No internet connection');
      verifyNever(() => launch(any()));
      expectNoNumber(result);
    });

    test('keeps the status and code of a refusal', () async {
      const refused = ForbiddenFailure(
          'You do not have access to this module.', 'ACCESS_DENIED');
      final result = await dialThrowing(refused);

      expect(result, isA<CallStartFailed>());
      final failure = (result as CallStartFailed).failure;
      expect(failure, same(refused));
      expect(failure.statusCode, 403);
      expect(failure.code, 'ACCESS_DENIED');
      expect(result.message, 'You do not have access to this module.');
      expect('$result', contains('ForbiddenFailure(403 ACCESS_DENIED)'));
      verifyNever(() => launch(any()));
    });

    test('keeps an ended session a session failure', () async {
      final result = await dialThrowing(const UnauthorizedFailure());

      expect((result as CallStartFailed).failure, isA<UnauthorizedFailure>());
      expect(result.message, 'Session expired, please log in again.');
    });

    test('takes a number out of a server message and keeps its type', () async {
      final result = await dialThrowing(BadResponseFailure(
          'The number $_number is on the do-not-call list.',
          statusCode: 409,
          code: 'TEST_REFUSED'));

      final failure = (result as CallStartFailed).failure;
      expect(failure, isA<BadResponseFailure>());
      expect(failure.statusCode, 409);
      expect(failure.code, 'TEST_REFUSED');
      expect(result.message, contains('is on the do-not-call list'));
      expect(result.message, contains(Redact.mask));
      verifyNever(() => launch(any()));
      expectNoNumber(result);
    });

    test('does the same for a 401 with its own message', () async {
      final result = await dialThrowing(
          UnauthorizedFailure(message: 'Wrong code for $_number.'));

      final failure = (result as CallStartFailed).failure;
      expect(failure, isA<UnauthorizedFailure>());
      expect(failure.message, 'Wrong code for ${Redact.mask}.');
      expectNoNumber(result);
    });

    test('masks a short (landline-length) number too', () async {
      final result = await dialThrowing(const BadResponseFailure(
          'Landline 0129-4 123 456 is blocked.',
          statusCode: 409,
          code: 'TEST_REFUSED'));

      final failure = (result as CallStartFailed).failure;
      expect(failure, isA<BadResponseFailure>());
      expect(failure.message, isNot(contains('123 456')));
      expect(failure.message, contains(Redact.mask));
      expect(failure.code, 'TEST_REFUSED');
    });

    test('keeps the kind, code and request id of a failure with no status',
        () async {
      final result = await dialThrowing(const BadResponseFailure(
          'Number 98765 43210 refused.',
          code: 'TEST_REFUSED',
          requestId: 'req-1'));

      final failure = (result as CallStartFailed).failure;
      expect(failure, isA<BadResponseFailure>());
      expect(failure.code, 'TEST_REFUSED');
      expect(failure.requestId, 'req-1');
      expect(failure.message, isNot(contains('98765')));
      expect(failure.message, contains(Redact.mask));
    });

    test('maps a raw dio timeout', () async {
      final result = await dialThrowing(DioException(
          requestOptions: RequestOptions(path: '/test/start-call'),
          type: DioExceptionType.connectionTimeout));

      expect(result, const CallStartFailed(TimeoutFailure()));
      verifyNever(() => launch(any()));
    });

    test('maps a raw dio refusal with its code', () async {
      final options = RequestOptions(path: '/test/start-call');
      final result = await dialThrowing(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
              requestOptions: options,
              statusCode: 403,
              data: {'code': 'ACCESS_DENIED', 'error': 'No access.'})));

      final failure = (result as CallStartFailed).failure;
      expect(failure, isA<ForbiddenFailure>());
      expect(failure.code, 'ACCESS_DENIED');
      expect(result.message, 'No access.');
    });

    test('drops a parse error that quotes the reply', () async {
      final result = await dialThrowing(
          const FormatException('Unexpected reply', '{"phone":"$_number"}'));

      expect(result, const CallStartFailed(ParseFailure()));
      expectNoNumber(result);
    });

    test('drops a type error from reading the reply', () async {
      when(() => startCall()).thenAnswer((_) async {
        final Object reply = {'phone': 9999999999};
        return (reply as Map)['phone'] as String;
      });

      final result = await dial();

      expect(result, const CallStartFailed(ParseFailure()));
      verifyNever(() => launch(any()));
      expectNoNumber(result);
    });

    test('drops any other error, which may quote the number', () async {
      final result = await dialThrowing(Exception('reply was $_number'));

      expect(result, const CallStartFailed(UnknownFailure()));
      verifyNever(() => launch(any()));
      expectNoNumber(result);
    });
  });

  group('the real launcher', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    late List<MethodCall> calls;

    setUp(() => calls = []);

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    test('hands tel: to another app, not to an in-app view', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      when(() => startCall()).thenAnswer((_) async => _number);

      final result = await _captured(
          printed, () => const CallLauncher().dial(startCall.call));

      expect(result, const CallDialerOpened());
      final args = calls.single.arguments as Map;
      expect(calls.single.method, 'launch');
      expect(args['url'], 'tel:$_number');
      expect(args['useWebView'], isFalse);
      expect(args['useSafariVC'], isFalse);
      expectNoNumber(result);
    });

    test('maps no handler on the phone to the dialer being unavailable',
        () async {
      when(() => startCall()).thenAnswer((_) async => _number);

      final result = await _captured(
          printed, () => const CallLauncher().dial(startCall.call));

      expect(result, const CallDialerUnavailable());
      expectNoNumber(result);
    });
  });

  test('is one app-wide helper in get_it', () {
    getIt.reset();
    addTearDown(getIt.reset);
    configureDependencies(AuthSession());

    expect(getIt.isRegistered<CallLauncher>(), isTrue);
    expect(getIt<CallLauncher>(), same(getIt<CallLauncher>()));
  });

  test(
      'the helper has no log, print or crash-report call and never asks '
      'canLaunchUrl', () {
    final code = File('lib/platform/call_launcher.dart')
        .readAsLinesSync()
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');

    for (final call in [
      'print(',
      'debugPrint(',
      'log(',
      'FirebaseCrashlytics',
      'CrashReporter',
      'canLaunchUrl(',
      'canLaunch(',
    ]) {
      expect(code, isNot(contains(call)), reason: call);
    }
  });
}
