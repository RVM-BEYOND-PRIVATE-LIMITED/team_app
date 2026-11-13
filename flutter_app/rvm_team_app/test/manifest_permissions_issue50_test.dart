import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// team_app #50, item 13 and check 2: the app asks for no call, call-log or
/// phone-state permission. The dialer hand-off (item 1,
/// lib/platform/call_launcher.dart) opens the phone's own dialer with the
/// number filled in, which needs none of them, and the Play data safety form
/// says "no call log". The main manifest must also declare the DIAL query that
/// item 1 asks for. CI checks the merged release manifest of the built APK the
/// same way (.github/workflows/flutter.yml); this test guards the manifests in
/// the repository.
const _forbidden = {
  'android.permission.CALL_PHONE',
  'android.permission.CALL_PRIVILEGED',
  'android.permission.READ_CALL_LOG',
  'android.permission.WRITE_CALL_LOG',
  'android.permission.PROCESS_OUTGOING_CALLS',
  'android.permission.ANSWER_PHONE_CALLS',
  'android.permission.READ_PHONE_STATE',
  'android.permission.READ_PHONE_NUMBERS',
};

/// Every permission a manifest asks for, in any `<uses-permission…>` form.
Set<String> _permissions(String manifest) => {
      for (final tag in RegExp(r'<uses-permission[^>]*>').allMatches(manifest))
        for (final name in RegExp(r'android:name\s*=\s*"([^"]+)"')
            .allMatches(tag.group(0)!))
          name.group(1)!,
    };

/// True when [manifest] has a `<queries>` `<intent>` with the action
/// `android.intent.action.DIAL` and a `tel` data scheme (team_app #50, item 1).
/// A commented-out entry does not count.
bool _dialQuery(String manifest) {
  final live = manifest.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  for (final queries
      in RegExp(r'<queries>([\s\S]*?)</queries>').allMatches(live)) {
    for (final intent in RegExp(r'<intent>([\s\S]*?)</intent>')
        .allMatches(queries.group(1)!)) {
      final body = intent.group(1)!;
      final dial = RegExp(
              r'<action[^>]*android:name\s*=\s*"android\.intent\.action\.DIAL"')
          .hasMatch(body);
      final tel =
          RegExp(r'<data[^>]*android:scheme\s*=\s*"tel"').hasMatch(body);
      if (dial && tel) return true;
    }
  }
  return false;
}

void main() {
  final manifests = [
    for (final set in ['main', 'debug', 'profile'])
      File('android/app/src/$set/AndroidManifest.xml'),
  ].where((f) => f.existsSync()).toList();

  test('finds the app manifests and reads their permissions', () {
    expect(manifests.map((f) => f.path),
        contains('android/app/src/main/AndroidManifest.xml'));
    final main = _permissions(manifests.first.readAsStringSync());
    // The permissions the app does use, so the check cannot pass by reading
    // nothing.
    expect(
        main,
        containsAll([
          'android.permission.INTERNET',
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.POST_NOTIFICATIONS',
        ]));
  });

  test('no manifest asks for a call, call-log or phone-state permission', () {
    for (final file in manifests) {
      final asked = _permissions(file.readAsStringSync());
      expect(asked.intersection(_forbidden), isEmpty, reason: file.path);
    }
  });

  test('the main manifest can see the dialer (item 1)', () {
    final main =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(_dialQuery(main), isTrue,
        reason: 'a <queries> intent for android.intent.action.DIAL on tel:');
  });

  test('the dialer check needs DIAL and tel: inside <queries>', () {
    const outside = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application>
    <activity android:name=".MainActivity">
      <intent-filter>
        <action android:name="android.intent.action.DIAL"/>
        <data android:scheme="tel"/>
      </intent-filter>
    </activity>
  </application>
</manifest>''';
    const viewOnly = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <queries>
    <intent>
      <action android:name="android.intent.action.VIEW"/>
      <data android:scheme="tel"/>
    </intent>
  </queries>
</manifest>''';
    const dial = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <queries>
    <intent>
      <action android:name="android.intent.action.PROCESS_TEXT"/>
      <data android:mimeType="text/plain"/>
    </intent>
    <intent>
      <action
          android:name="android.intent.action.DIAL" />
      <data android:scheme="tel" />
    </intent>
  </queries>
</manifest>''';
    const commented = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <queries>
    <!--
    <intent>
      <action android:name="android.intent.action.DIAL"/>
      <data android:scheme="tel"/>
    </intent>
    -->
  </queries>
</manifest>''';
    expect(_dialQuery(outside), isFalse);
    expect(_dialQuery(commented), isFalse);
    expect(_dialQuery(viewOnly), isFalse);
    expect(_dialQuery(dial), isTrue);
  });

  test('the check itself catches every form of the tag', () {
    const sample = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-permission android:name="android.permission.CALL_PHONE"/>
  <uses-permission-sdk-23 android:name="android.permission.READ_CALL_LOG" />
  <uses-permission
      android:maxSdkVersion="28"
      android:name="android.permission.READ_PHONE_STATE"/>
</manifest>''';
    expect(_permissions(sample).intersection(_forbidden), {
      'android.permission.CALL_PHONE',
      'android.permission.READ_CALL_LOG',
      'android.permission.READ_PHONE_STATE',
    });
  });
}
