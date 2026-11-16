import 'package:flutter/services.dart';

/// Voice typing for a remark (team_app #51, item 10). It asks Android's own
/// speech prompt (`RecognizerIntent.ACTION_RECOGNIZE_SPEECH`) through a small
/// platform channel; the phone's speech service holds the microphone
/// permission, so the app declares no `RECORD_AUDIO`. The recogniser is asked
/// to prefer offline recognition where the phone supports it, because the
/// remark is lead data and the speech service is an outside system.
///
/// On iOS, or a phone with no recogniser, it returns null and the screen keeps
/// the keyboard.
abstract final class VoiceRemarks {
  static const channel = MethodChannel('team_rvm/voice');

  static Future<String?> listen() async {
    try {
      final text = await channel.invokeMethod<String>('recognize');
      final trimmed = text?.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
