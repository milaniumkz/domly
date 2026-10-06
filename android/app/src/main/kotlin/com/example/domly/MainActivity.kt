package com.example.domly

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "domly/offer_alert_sound"
    private var player: MediaPlayer? = null
    private var previousAlarmVolume: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prime" -> {
                        primeOfferAlert()
                        result.success(null)
                    }
                    "start" -> {
                        val volume = (call.argument<Double>("volume") ?: 1.0).coerceIn(0.0, 1.0).toFloat()
                        val soundIndex = (call.argument<Int>("soundIndex") ?: 0).coerceIn(0, 20)
                        startOfferAlert(volume, soundIndex)
                        result.success(null)
                    }
                    "stop" -> {
                        stopOfferAlert()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun primeOfferAlert() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun startOfferAlert(volume: Float, soundIndex: Int) {
        if (player?.isPlaying == true) {
            vibrateAlert()
            return
        }
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)

        stopPlayerOnly()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val source = if (soundIndex == 0) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } else {
            null
        }
        player = if (source != null) {
            MediaPlayer.create(this, source)
        } else {
            val soundResId = listOf(
                R.raw.domly_alert_01,
                R.raw.domly_alert_02,
                R.raw.domly_alert_03,
                R.raw.domly_alert_04,
                R.raw.domly_alert_05,
                R.raw.domly_alert_06,
                R.raw.domly_alert_07,
                R.raw.domly_alert_08,
                R.raw.domly_alert_09,
                R.raw.domly_alert_10,
                R.raw.domly_alert_11,
                R.raw.domly_alert_12,
                R.raw.domly_alert_13,
                R.raw.domly_alert_14,
                R.raw.domly_alert_15,
                R.raw.domly_alert_16,
                R.raw.domly_alert_17,
                R.raw.domly_alert_18,
                R.raw.domly_alert_19,
                R.raw.domly_alert_20
            )[soundIndex - 1]
            MediaPlayer.create(this, soundResId, attributes, 0)
        }?.apply {
            isLooping = true
            setVolume(volume, volume)
            start()
        }
        vibrateAlert()
    }

    private fun stopOfferAlert() {
        stopPlayerOnly()
        val restoreVolume = previousAlarmVolume
        if (restoreVolume != null) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, restoreVolume, 0)
            previousAlarmVolume = null
        }
    }

    private fun stopPlayerOnly() {
        player?.run {
            try {
                stop()
            } catch (_: IllegalStateException) {
            }
            release()
        }
        player = null
    }

    private fun vibrateAlert() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        val pattern = longArrayOf(0, 700, 180, 700, 180, 1100)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    override fun onDestroy() {
        stopOfferAlert()
        super.onDestroy()
    }
}
