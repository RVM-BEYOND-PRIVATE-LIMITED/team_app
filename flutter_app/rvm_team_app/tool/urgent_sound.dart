// Makes android/app/src/main/res/raw/team_rvm_urgent.wav, the sound of the
// urgent notification channel (team_app #50, item 8). The sound is synthesised
// here, so the file holds no third-party recording and no licence.
//
//   cd flutter_app/rvm_team_app && dart run tool/urgent_sound.dart
//
// test/urgent_channel_issue50_test.dart checks that the committed file is what
// this makes. Changing the sound later keeps the channel: the channel stores
// the resource's name, not its contents.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const urgentSoundSampleRate = 22050;

/// Where the file goes, from the app's directory.
const urgentSoundPath = 'android/app/src/main/res/raw/team_rvm_urgent.wav';

/// A bright rising triad (A5, C#6, E6) struck twice: short, clearly not the
/// phone's own notification sound, and not harsh.
Uint8List urgentChimeWav() {
  const rate = urgentSoundSampleRate;
  const notes = [880.0, 1108.73, 1318.51];
  const step = 0.11; // seconds between the notes of one triad
  const repeat = 0.5; // seconds between the two triads
  const ring = 0.45; // how long each note rings
  final length = ((repeat + 2 * step + ring) * rate).ceil();
  final mix = Float64List(length);
  final ringSamples = (ring * rate).round();
  final release = 0.02 * rate; // a 20 ms fade at the end of each note

  for (final start in [0.0, repeat]) {
    for (var n = 0; n < notes.length; n++) {
      final offset = ((start + n * step) * rate).round();
      final frequency = notes[n];
      for (var i = 0; i < ringSamples; i++) {
        final t = i / rate;
        // 4 ms attack, a bell-like exponential decay, then the release, so
        // no note starts or stops with a click.
        final envelope = math.min(1.0, t / 0.004) *
            math.exp(-t / 0.13) *
            math.min(1.0, (ringSamples - 1 - i) / release);
        final w = 2 * math.pi * frequency * t;
        mix[offset + i] += envelope *
            (math.sin(w) + 0.35 * math.sin(2 * w) + 0.12 * math.sin(3 * w));
      }
    }
  }

  var peak = 0.0;
  for (final v in mix) {
    peak = math.max(peak, v.abs());
  }
  final samples = Int16List(length);
  for (var i = 0; i < length; i++) {
    // Peak at about -3 dBFS.
    samples[i] = (mix[i] / peak * 0.7 * 32767).round();
  }
  return _wav(samples, rate);
}

/// A RIFF/WAVE file: 16-bit PCM, one channel.
Uint8List _wav(Int16List samples, int rate) {
  final data = samples.lengthInBytes;
  final out = ByteData(44 + data);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little); // fmt chunk size
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, rate, Endian.little);
  out.setUint32(28, rate * 2, Endian.little); // bytes per second
  out.setUint16(32, 2, Endian.little); // bytes per frame
  out.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  out.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(44 + 2 * i, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

void main() {
  File(urgentSoundPath).writeAsBytesSync(urgentChimeWav());
  stdout.writeln('Wrote $urgentSoundPath');
}
