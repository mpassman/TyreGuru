package com.tyreguru.app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/** Answers the page's native requests. Same messages as the iPhone app (see WebContainer.swift). */
class Bridge(private val act: MainActivity, private val web: WebView) {
    private val ctx: Context = act.applicationContext
    private val stateFile get() = File(ctx.filesDir, "tireguru-state.json")
    private var wantGeo = false

    fun js(code: String) { web.post { web.evaluateJavascript(code, null) } }

    fun loadState(): String? = try { if (stateFile.exists()) stateFile.readText() else null } catch (e: Exception) { null }

    @JavascriptInterface
    fun post(name: String, body: String) {
        try {
            when (name) {
                "store" -> stateFile.writeText(body)
                "geo" -> act.runOnUiThread { geo() }
                "http" -> http(body)
                "alerts" -> alerts(JSONObject(body))
                "tyrewiz" -> { TyreWizBle.sink = { fn, json -> js("window.$fn&&window.$fn($json)") }
                               TyreWizBle.visible = { act.visible }
                               TyreWizBle.command(JSONObject(body)) }
                "garmin" -> js("window.__garminStatus&&window.__garminStatus('Sending to a Garmin Edge is not set up in the Android build yet.')")
                "health" -> js("window.__nativeHealthErr&&window.__nativeHealthErr('Health Connect is not set up in this Android build. Connect Intervals.icu or Strava, or import files.')")
            }
        } catch (e: Exception) { /* a bad message from the page must never crash the app */ }
    }

    // ---- location (approximate, once)
    fun onPermissions(r: Map<String, Boolean>) {
        if (wantGeo && (r[Manifest.permission.ACCESS_COARSE_LOCATION] == true || r[Manifest.permission.ACCESS_FINE_LOCATION] == true)) geo()
        else if (wantGeo) { wantGeo = false; js("window.__nativeGeoErr&&window.__nativeGeoErr('Location is off for TyreGuru. Turn it on in Android Settings.')") }
        TyreWizBle.onPermissions(r)
    }

    private fun geo() {
        wantGeo = true
        if (!act.has(Manifest.permission.ACCESS_COARSE_LOCATION) && !act.has(Manifest.permission.ACCESS_FINE_LOCATION)) {
            act.ask(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION)); return
        }
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        fun done(l: Location) { wantGeo = false; js("window.__nativeGeo&&window.__nativeGeo({lat:${l.latitude},lon:${l.longitude},altM:${l.altitude}})") }
        fun fail() { wantGeo = false; js("window.__nativeGeoErr&&window.__nativeGeoErr('Location could not be found. Try again outdoors or check your connection.')") }
        val prov = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.PASSIVE_PROVIDER).firstOrNull { try { lm.isProviderEnabled(it) } catch (e: Exception) { false } }
        if (prov == null) { fail(); return }
        try {
            if (Build.VERSION.SDK_INT >= 30) lm.getCurrentLocation(prov, null, ContextCompat.getMainExecutor(ctx)) { l -> if (l != null) done(l) else fail() }
            else { val l = lm.getLastKnownLocation(prov); if (l != null) done(l) else fail() }
        } catch (e: SecurityException) { fail() }
    }

    // ---- web requests for the connected services only
    private val hosts = listOf("strava.com", "intervals.icu", "withings.net", "whoop.com")
    private fun http(text: String) {
        val o = JSONObject(text)
        val id = o.getString("id"); val u = URL(o.getString("url"))
        if (u.protocol != "https" || hosts.none { u.host == it || u.host.endsWith(".$it") }) return
        Thread {
            var status = 0; var body = ""; var err = "null"
            try {
                val c = u.openConnection() as HttpURLConnection
                c.requestMethod = o.optString("method", "GET"); c.connectTimeout = 20000; c.readTimeout = 40000
                val h = o.optJSONObject("headers"); h?.keys()?.forEach { k -> c.setRequestProperty(k, h.getString(k)) }
                if (!o.isNull("body")) { c.doOutput = true; c.outputStream.use { it.write(o.getString("body").toByteArray()) } }
                status = c.responseCode
                val st = if (status >= 400) c.errorStream else c.inputStream
                body = st?.bufferedReader()?.readText() ?: ""
            } catch (e: Exception) { err = JSONObject.quote(e.message ?: "network error") }
            js("window.__nativeHttp(${JSONObject.quote(id)},$status,${JSONObject.quote(body)},$err)")
        }.start()
    }

    // ---- alerts: sound, vibration, sealant-check reminders
    private fun alerts(o: JSONObject) {
        when (o.optString("cmd")) {
            "alert" -> {
                val kind = o.optString("kind")
                if (o.optBoolean("vib", true)) vibrate(kind)
                if (o.optBoolean("sound", true)) Thread { play(kind) }.start()
            }
            "remind" -> schedule(o.optJSONArray("items") ?: JSONArray())
        }
    }

    private fun vibrate(kind: String) {
        val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) (ctx.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
                          else @Suppress("DEPRECATION") ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        val loud = kind == "danger" || kind == "mi0"
        v.vibrate(VibrationEffect.createWaveform(if (loud) longArrayOf(0, 200, 100, 200, 100, 200) else longArrayOf(0, 150), -1))
    }

    private fun tone(sr: Int, parts: List<DoubleArray>, total: Double, f: (Double, Double) -> Double): ShortArray {
        val n = (total * sr).toInt(); val out = ShortArray(n)
        for (i in 0 until n) { val t = i.toDouble() / sr; out[i] = (f(t, total) * 32767 * 0.5).toInt().toShort() }
        return out
    }

    private fun play(kind: String) {
        val sr = 22050
        fun sq(x: Double) = if (sin(x) >= 0) 1.0 else -1.0
        val data: ShortArray = when (kind) {
            "danger" -> tone(sr, emptyList(), 0.74) { t, _ ->
                val k = (t / 0.22).toInt(); val lt = t - k * 0.22
                if (k < 3 && lt < 0.14) sq(2 * PI * 880 * t) else 0.0 }
            "mi50" -> tone(sr, emptyList(), 0.74) { t, _ ->
                val k = (t / 0.22).toInt(); val lt = t - k * 0.22
                if (k < 3 && lt < 0.14) sq(2 * PI * 3100 * t) else 0.0 }
            "mi0" -> tone(sr, emptyList(), 4.0) { t, _ ->
                val c = (t % 1.0); val f = if (c < 0.5) 700 + 1000 * (c / 0.5) else 1700 - 1000 * ((c - 0.5) / 0.5)
                sq(2 * PI * f * t) }
            else -> tone(sr, emptyList(), 1.2) { t, _ -> sin(2 * PI * 1318 * t) * exp(-t * 4) }
        }
        val at = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(sr).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(data.size * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
        at.write(data, 0, data.size); at.play()
        Thread.sleep((data.size * 1000L / sr) + 200); at.release()
    }

    private fun schedule(items: JSONArray) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val prefs = ctx.getSharedPreferences("tg", Context.MODE_PRIVATE)
        // cancel the previous set, then add the new one
        val old = prefs.getStringSet("remind", emptySet()) ?: emptySet()
        for (id in old) am.cancel(pi(id, "", ""))
        val ids = HashSet<String>()
        for (i in 0 until items.length()) {
            val it = items.getJSONObject(i)
            val id = it.optString("id"); val at = it.optDouble("at", 0.0).toLong()
            if (at - System.currentTimeMillis() < 5000) continue
            ids.add(id)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi(id, it.optString("title", "TyreGuru"), it.optString("body")))
        }
        prefs.edit().putStringSet("remind", ids).apply()
    }

    private fun pi(id: String, title: String, body: String): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java).putExtra("id", id).putExtra("title", title).putExtra("body", body)
        return PendingIntent.getBroadcast(ctx, id.hashCode(), i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}
