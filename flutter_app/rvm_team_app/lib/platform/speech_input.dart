import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_crash.dart';

/// Voice typing for a remark (team_app #51, item 10): the phone's own speech
/// prompt, opened by MainActivity with `RecognizerIntent` on the
/// `team_rvm/speech_input` channel. The phone's speech service holds the
/// microphone, so the app asks for no `RECORD_AUDIO` permission. Offline
/// recognition is preferred where the phone supports it.
///
/// The recognised text is lead data. It is handed back to the caller and is
/// never printed, logged or sent in a crash report: an error is reported only
/// by a fixed reason.
///
/// Android only. Elsewhere [isAvailable] is false and [listen] gives null with
/// nothing sent.
class SpeechInput {
  SpeechInput({MethodChannel? channel, bool Function()? supported})
      : _channel = channel ?? const MethodChannel(channelName),
        _supported = supported ?? _isAndroid;

  /// The app's one speech prompt.
  static final SpeechInput instance = SpeechInput();

  /// The channel MainActivity.kt answers.
  static const channelName = 'team_rvm/speech_input';

  /// Refusals MainActivity sends on purpose: the prompt is already open, or the
  /// phone has no speech service. Neither is an error worth reporting.
  static const _expectedRefusals = {'busy', 'unavailable'};

  final MethodChannel _channel;
  final bool Function() _supported;
  bool _listening = false;

  /// True while the speech prompt is open.
  bool get isListening => _listening;

  /// Whether the phone has a speech service to open, so a mic button can be
  /// hidden when it has none.
  Future<bool> isAvailable() async {
    if (!_supported()) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } catch (e, st) {
      await CrashReporter.record(e, st, reason: 'speech_input:isAvailable');
      return false;
    }
  }

  /// Opens the speech prompt and gives the recognised text, trimmed.
  ///
  /// Null when the person cancels or says nothing, when the phone has no
  /// speech service, off Android, or while a prompt is already open (a double
  /// tap opens one prompt, and only the first call gets its text).
  Future<String?> listen() async {
    if (!_supported() || _listening) return null;
    _listening = true;
    try {
      final text = (await _channel.invokeMethod<String>('listen'))?.trim();
      return text == null || text.isEmpty ? null : text;
    } on MissingPluginException {
      // No handler on this host (an engine without MainActivity).
      return null;
    } on PlatformException catch (e, st) {
      if (!_expectedRefusals.contains(e.code)) {
        await CrashReporter.record(e, st, reason: 'speech_input:listen');
      }
      return null;
    } catch (e, st) {
      await CrashReporter.record(e, st, reason: 'speech_input:listen');
      return null;
    } finally {
      _listening = false;
    }
  }

  static bool _isAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
