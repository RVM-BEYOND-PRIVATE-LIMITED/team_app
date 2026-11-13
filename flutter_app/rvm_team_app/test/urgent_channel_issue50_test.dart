import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rvm_team_app/push/push_service.dart';

import '../tool/urgent_sound.dart'
    show urgentChimeWav, urgentSoundPath, urgentSoundSampleRate;

/// team_app #50, item 8: the urgent channel is created at start-up with its
/// own sound, next to the existing alerts channel, and its sound ships in the
/// release build.
class _MockAndroidPlugin extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() => registerFallbackValue(
      const AndroidNotificationChannel('fallback', 'Fallback')));

  group('the channels', () {
    AndroidNotificationChannel channel(String id) =>
        teamNotificationChannels.singleWhere((c) => c.id == id);

    test('alerts stays as it was; urgent is added', () {
      expect([for (final c in teamNotificationChannels) c.id],
          ['team_rvm_alerts', 'team_rvm_urgent']);
      final alerts = channel('team_rvm_alerts');
      expect(alerts.name, 'Team RVM alerts');
      expect(alerts.importance, Importance.max);
      expect(alerts.playSound, isTrue);
      expect(alerts.sound, isNull); // the phone's own notification sound
    });

    test('urgent has the highest importance and its own sound', () {
      final urgent = channel(urgentChannelId);
      expect(urgent.id, 'team_rvm_urgent');
      expect(urgent.name, 'Team RVM urgent');
      expect(urgent.importance, Importance.max);
      expect(urgent.playSound, isTrue);
      expect(urgent.enableVibration, isTrue);
      final sound = urgent.sound;
      expect(sound, isA<RawResourceAndroidNotificationSound>());
      expect(sound!.sound, 'team_rvm_urgent');
    });

    test('both are created, and one failure does not stop the other', () async {
      final android = _MockAndroidPlugin();
      final created = <String>[];
      when(() => android.createNotificationChannel(any()))
          .thenAnswer((call) async {
        final c = call.positionalArguments.single as AndroidNotificationChannel;
        if (c.id == 'team_rvm_alerts') throw Exception('test failure');
        created.add(c.id);
      });

      await createTeamNotificationChannels(android);

      verify(() => android.createNotificationChannel(any())).called(2);
      expect(created, ['team_rvm_urgent']);
    });

    test('a foreground push is drawn on urgent only when it names it', () {
      expect(isUrgentChannel('team_rvm_urgent'), isTrue);
      expect(isUrgentChannel(' team_rvm_urgent '), isTrue);
      expect(isUrgentChannel('team_rvm_alerts'), isFalse);
      expect(isUrgentChannel(''), isFalse);
      expect(isUrgentChannel(null), isFalse);
    });
  });

  group('the urgent sound', () {
    final file = File(urgentSoundPath);

    test('is res/raw/<the channel\'s sound>.wav', () {
      expect(urgentSoundPath,
          'android/app/src/main/res/raw/$urgentSoundResource.wav');
      expect(file.existsSync(), isTrue);
    });

    test('is a short 16-bit mono PCM WAV Android can play', () {
      final bytes = ByteData.sublistView(file.readAsBytesSync());
      String ascii(int at, int n) =>
          String.fromCharCodes(List.generate(n, (i) => bytes.getUint8(at + i)));
      expect(ascii(0, 4), 'RIFF');
      expect(ascii(8, 4), 'WAVE');
      expect(ascii(12, 4), 'fmt ');
      expect(bytes.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(bytes.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(bytes.getUint32(24, Endian.little), urgentSoundSampleRate);
      expect(bytes.getUint16(34, Endian.little), 16, reason: 'bits');
      expect(ascii(36, 4), 'data');
      final data = bytes.getUint32(40, Endian.little);
      expect(44 + data, bytes.lengthInBytes);
      final seconds = data / 2 / urgentSoundSampleRate;
      expect(seconds, inInclusiveRange(0.5, 2.0));
    });

    test('is what tool/urgent_sound.dart makes', () {
      final committed = file.readAsBytesSync();
      final made = urgentChimeWav();
      expect(committed.length, made.length);
      expect(committed.sublist(0, 44), made.sublist(0, 44));
      // Allow one step of rounding between machines' sine functions.
      final a = ByteData.sublistView(committed);
      final b = ByteData.sublistView(made);
      var peak = 0;
      for (var i = 44; i < committed.length; i += 2) {
        final x = a.getInt16(i, Endian.little);
        expect((x - b.getInt16(i, Endian.little)).abs(), lessThanOrEqualTo(1),
            reason: 'sample ${(i - 44) ~/ 2}');
        peak = x.abs() > peak ? x.abs() : peak;
      }
      // Loud enough to hear, with headroom (about -3 dBFS).
      expect(peak / 32767, inInclusiveRange(0.6, 0.8));
    });

    test('survives resource shrinking in the release build', () {
      // Only Dart names these resources, so the shrinker would drop them. The
      // large icon is the one every notification PushService draws carries.
      final keep = File('android/app/src/main/res/raw/keep.xml');
      expect(keep.existsSync(), isTrue);
      final kept = RegExp(r'tools:keep="([^"]*)"')
          .firstMatch(keep.readAsStringSync())
          ?.group(1)
          ?.split(',')
          .map((r) => r.trim());
      expect(
          kept,
          containsAll([
            '@raw/$urgentSoundResource',
            '@drawable/ic_notification_large'
          ]));
      expect(
          File('android/app/src/main/res/drawable-nodpi/'
                  'ic_notification_large.png')
              .existsSync(),
          isTrue);
    });
  });
}
