import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/platform/speech_input.dart';

/// team_app #51, item 10: voice typing for a remark through the phone's own
/// speech prompt. MainActivity opens RecognizerIntent on the
/// `team_rvm/speech_input` channel; the channel is mocked here, so each test
/// sees exactly what MainActivity would be asked and what it could answer.
const _channel = MethodChannel(SpeechInput.channelName);

/// A made-up remark, as the speech service would hand it back.
const _spoken = 'Test Student will call back after the exam';

typedef _Answer = Future<Object?> Function(MethodCall call);

/// Answers the channel with [answer] and returns the methods it was sent.
List<String> _mockChannel(_Answer answer) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) {
    calls.add(call.method);
    return answer(call);
  });
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));
  return calls;
}

/// Everything the app prints while a test runs.
List<String> _capturePrints() {
  final printed = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) => printed.add('$message');
  addTearDown(() => debugPrint = original);
  return printed;
}

SpeechInput _android() => SpeechInput(supported: () => true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('listen', () {
    test('asks MainActivity to listen and gives the text back, trimmed',
        () async {
      final calls = _mockChannel((_) async => '  $_spoken \n');

      expect(await _android().listen(), _spoken);
      expect(calls, ['listen']);
    });

    test('a cancelled prompt or one that heard nothing gives null', () async {
      final answers = <Object?>[null, '', '   '];
      _mockChannel((_) async => answers.removeAt(0));
      final speech = _android();

      expect(await speech.listen(), isNull);
      expect(await speech.listen(), isNull);
      expect(await speech.listen(), isNull);
    });

    test('a phone with no speech service gives null and reports nothing',
        () async {
      final printed = _capturePrints();
      _mockChannel((_) async => throw PlatformException(
          code: 'unavailable', message: 'This phone has no speech service.'));

      expect(await _android().listen(), isNull);
      expect(printed, isEmpty);
    });

    test('an engine without MainActivity gives null', () async {
      // No handler on the channel: MissingPluginException.
      expect(await _android().listen(), isNull);
    });

    test('off Android nothing is sent and the answer is null', () async {
      final calls = _mockChannel((_) async => _spoken);
      final speech = SpeechInput(supported: () => false);

      expect(await speech.listen(), isNull);
      expect(await speech.isAvailable(), isFalse);
      expect(calls, isEmpty);
    });

    test('a second call while the prompt is open opens no second prompt',
        () async {
      final heard = Completer<String?>();
      final calls = _mockChannel((_) => heard.future);
      final speech = _android();

      final first = speech.listen();
      expect(speech.isListening, isTrue);
      expect(await speech.listen(), isNull);

      heard.complete(_spoken);
      expect(await first, _spoken);
      expect(speech.isListening, isFalse);
      expect(calls, ['listen']);
    });

    test('the prompt can be opened again after an error', () async {
      var fail = true;
      _mockChannel((_) async {
        if (fail) {
          fail = false;
          throw PlatformException(code: 'busy');
        }
        return _spoken;
      });
      final speech = _android();

      expect(await speech.listen(), isNull);
      expect(speech.isListening, isFalse);
      expect(await speech.listen(), _spoken);
    });
  });

  group('the recognised text is never logged', () {
    test('nothing is printed when the text comes back', () async {
      final printed = _capturePrints();
      _mockChannel((_) async => _spoken);

      expect(await _android().listen(), _spoken);
      expect(printed, isEmpty);
    });

    test('an unexpected failure is reported by a fixed reason only', () async {
      final printed = _capturePrints();
      _mockChannel((_) async =>
          throw PlatformException(code: 'error', message: 'Recognizer failed'));

      expect(await _android().listen(), isNull);
      expect(printed, isNotEmpty);
      expect(printed.first, contains('speech_input:listen'));
      expect(printed.join('\n'), isNot(contains(_spoken)));
    });

    test('the wrapper source has no print or log call', () {
      final source = File('lib/platform/speech_input.dart').readAsStringSync();
      for (final call in ['print(', 'debugPrint(', 'log(', 'developer.']) {
        expect(source, isNot(contains(call)), reason: call);
      }
    });
  });

  group('isAvailable', () {
    test('passes on what MainActivity finds', () async {
      final answers = <Object?>[true, false, null];
      final calls = _mockChannel((_) async => answers.removeAt(0));
      final speech = _android();

      expect(await speech.isAvailable(), isTrue);
      expect(await speech.isAvailable(), isFalse);
      expect(await speech.isAvailable(), isFalse);
      expect(calls, ['isAvailable', 'isAvailable', 'isAvailable']);
    });

    test('an engine without MainActivity has no speech service', () async {
      expect(await _android().isAvailable(), isFalse);
    });
  });
}
