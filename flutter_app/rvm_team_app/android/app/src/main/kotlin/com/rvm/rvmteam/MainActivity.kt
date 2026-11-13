package com.rvm.rvmteam

import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** The Dart call waiting for the speech prompt to close, if one is open. */
    private var pendingSpeech: MethodChannel.Result? = null

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
        // Voice typing for a remark (team_app #51, item 10): the phone's own
        // speech prompt, opened with RecognizerIntent. The speech service holds
        // the microphone, so the app asks for no RECORD_AUDIO permission. The
        // Dart side is lib/platform/speech_input.dart. The recognised text is
        // lead data: it is only handed back, never logged.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPEECH_INPUT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(speechIntent().resolveActivity(packageManager) != null)
                    "listen" -> listen(result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Free-form speech, one result, offline where the phone can do it: the
     * remark is lead data and the speech service is outside the app.
     * EXTRA_PREFER_OFFLINE is read from Android 6 (API 23); older phones
     * ignore it and may recognise online.
     */
    private fun speechIntent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
    }

    private fun listen(result: MethodChannel.Result) {
        if (pendingSpeech != null) {
            result.error("busy", "The speech prompt is already open.", null)
            return
        }
        val intent = speechIntent()
        // Finding the speech service needs the RECOGNIZE_SPEECH entry under
        // <queries> in AndroidManifest.xml (package visibility, Android 11+).
        if (intent.resolveActivity(packageManager) == null) {
            result.error("unavailable", "This phone has no speech service.", null)
            return
        }
        pendingSpeech = result
        try {
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (e: ActivityNotFoundException) {
            pendingSpeech = null
            result.error("unavailable", "This phone has no speech service.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val speech = pendingSpeech
        if (requestCode == SPEECH_REQUEST_CODE && speech != null) {
            pendingSpeech = null
            // Cancelled, nothing heard, or an error: no text.
            val text = if (resultCode == RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            } else {
                null
            }
            speech.success(text)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        // The prompt can outlive this activity; never leave the Dart call open.
        pendingSpeech?.success(null)
        pendingSpeech = null
        super.onDestroy()
    }

    private companion object {
        const val SECURE_WINDOW_CHANNEL = "team_rvm/secure_window"
        const val SPEECH_INPUT_CHANNEL = "team_rvm/speech_input"

        /** Fits in 16 bits, so it stays valid if this becomes a FragmentActivity. */
        const val SPEECH_REQUEST_CODE = 5110
    }
}
