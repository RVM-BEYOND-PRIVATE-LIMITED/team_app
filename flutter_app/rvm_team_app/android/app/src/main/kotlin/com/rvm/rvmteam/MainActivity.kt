package com.rvm.rvmteam

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The screenshot block for sensitive screens (team_app #52, item 1).
        // FLAG_SECURE also blanks the app-switcher preview and screen
        // recordings. The Dart side (lib/platform/secure_window.dart) counts
        // the screens that ask for it and sends only the first "enable" and
        // the last "disable".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_WINDOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> runOnUiThread {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Voice typing for a CRM remark (team_app #51, item 10). Android's own
        // recogniser prompt reads the microphone under its own permission, so
        // the app never declares RECORD_AUDIO. Prefer offline recognition: a
        // remark is lead data and the speech service is an outside system.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognize" -> {
                        if (voiceResult != null) {
                            result.error("BUSY", "The speech prompt is already open.", null)
                            return@setMethodCallHandler
                        }
                        voiceResult = result
                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(
                                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                            )
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN")
                            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak the remark")
                        }
                        try {
                            startActivityForResult(intent, VOICE_REQUEST)
                        } catch (e: Exception) {
                            voiceResult = null
                            result.error("NO_RECOGNIZER", "No speech service is available.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var voiceResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VOICE_REQUEST) {
            val pending = voiceResult
            voiceResult = null
            if (resultCode == Activity.RESULT_OK) {
                val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                pending?.success(matches?.firstOrNull())
            } else {
                pending?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private companion object {
        const val SECURE_WINDOW_CHANNEL = "team_rvm/secure_window"
        const val VOICE_CHANNEL = "team_rvm/voice"
        const val VOICE_REQUEST = 7102
    }
}
