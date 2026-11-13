import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rvm_team_app/platform/speech_input.dart';

/// team_app #51, item 10: voice typing goes through the phone's speech prompt
/// (RecognizerIntent), so the app itself asks for no microphone permission.
/// This test fails if any app manifest asks for RECORD_AUDIO, or if the
/// `<queries>` entry that lets MainActivity find the speech prompt is gone. CI
/// checks the merged release manifest of the built APK for RECORD_AUDIO too
/// (.github/workflows/flutter.yml).
const _microphone = 'android.permission.RECORD_AUDIO';
const _recognizeSpeech = 'android.speech.action.RECOGNIZE_SPEECH';
const _mainActivity =
    'android/app/src/main/kotlin/com/rvm/rvmteam/MainActivity.kt';

/// Every permission a manifest asks for, in any `<uses-permission…>` form.
Set<String> _permissions(String manifest) => {
      for (final tag in RegExp(r'<uses-permission[^>]*>').allMatches(manifest))
        for (final name in RegExp(r'android:name\s*=\s*"([^"]+)"')
            .allMatches(tag.group(0)!))
          name.group(1)!,
    };

/// The actions of the intents listed under `<queries>`, comments left out.
Set<String> _queriedActions(String manifest) {
  final code = manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  return {
    for (final block
        in RegExp(r'<queries>(.*?)</queries>', dotAll: true).allMatches(code))
      for (final action
          in RegExp(r'<action\s+android:name\s*=\s*"([^"]+)"')
              .allMatches(block.group(1)!))
        action.group(1)!,
  };
}

void main() {
  final manifests = [
    for (final set in ['main', 'debug', 'profile'])
      File('android/app/src/$set/AndroidManifest.xml'),
  ].where((f) => f.existsSync()).toList();

  test('finds the app manifests and reads their permissions', () {
    expect(manifests.map((f) => f.path),
        contains('android/app/src/main/AndroidManifest.xml'));
    // A permission the app does use, so the check cannot pass by reading
    // nothing.
    expect(_permissions(manifests.first.readAsStringSync()),
        contains('android.permission.INTERNET'));
  });

  test('no manifest asks for the microphone', () {
    for (final file in manifests) {
      expect(_permissions(file.readAsStringSync()), isNot(contains(_microphone)),
          reason: file.path);
    }
  });

  test('the check itself catches every form of the tag', () {
    for (final tag in [
      '<uses-permission android:name="$_microphone"/>',
      '<uses-permission-sdk-23 android:name="$_microphone" />',
      '<uses-permission\n    android:maxSdkVersion="28"\n'
          '    android:name="$_microphone"/>',
    ]) {
      expect(_permissions('<manifest>$tag</manifest>'), contains(_microphone),
          reason: tag);
    }
  });

  test('the manifest lets MainActivity find the speech prompt', () {
    final main = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(_queriedActions(main), contains(_recognizeSpeech));
    // A commented-out entry does not count.
    expect(
        _queriedActions('<queries><!-- <intent><action android:name='
            '"$_recognizeSpeech"/></intent> --></queries>'),
        isEmpty);
  });

  test('MainActivity opens free-form, offline-first speech on the same channel',
      () {
    final kotlin = File(_mainActivity).readAsStringSync();
    expect(kotlin, contains('"${SpeechInput.channelName}"'));
    expect(kotlin, contains('RecognizerIntent.ACTION_RECOGNIZE_SPEECH'));
    expect(kotlin, contains('RecognizerIntent.LANGUAGE_MODEL_FREE_FORM'));
    expect(kotlin,
        contains('putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)'));
    // Opens the system prompt, never its own recogniser (which would need the
    // microphone permission).
    expect(kotlin, isNot(contains('SpeechRecognizer')));
    // The recognised text is never written to the device log.
    expect(kotlin, isNot(contains('android.util.Log')));
    expect(kotlin, isNot(contains('println(')));
  });
}
