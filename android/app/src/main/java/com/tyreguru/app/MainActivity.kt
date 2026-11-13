package com.tyreguru.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import java.util.Locale

/** One WebView that loads the same index.html as the iPhone app. Bridge.kt answers the page's native requests. */
class MainActivity : AppCompatActivity() {
    lateinit var web: WebView
    lateinit var bridge: Bridge
    var visible = false

    private val perms = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { r ->
        bridge.onPermissions(r)
    }
    fun ask(list: Array<String>) = perms.launch(list)
    fun has(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        web.setBackgroundColor(Color.BLACK)
        setContentView(web)
        bridge = Bridge(this, web)
        MainHolder.act = this
        TyreWizBle.attach(applicationContext)
        val s = web.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        val loader = WebViewAssetLoader.Builder().addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(this)).build()
        val saved = bridge.loadState()
        val metric = Locale.getDefault().country != "US"
        val shim = """
            (function(){
              const mk=n=>({postMessage:m=>TGNative.post(n,typeof m==='string'?m:JSON.stringify(m))});
              window.webkit={messageHandlers:{geo:mk('geo'),store:mk('store'),http:mk('http'),alerts:mk('alerts'),garmin:mk('garmin'),tyrewiz:mk('tyrewiz'),health:mk('health')}};
              window.__metric=$metric;
              ${if (saved != null) "window.__nativeState=" + JSONObject.quote(saved) + ";" else ""}
            })();
        """.trimIndent()
        web.addJavascriptInterface(bridge, "TGNative")
        val useDocStart = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        if (useDocStart) WebViewCompat.addDocumentStartJavaScript(web, shim, setOf("https://appassets.androidplatform.net"))
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? = loader.shouldInterceptRequest(r.url)
            override fun onPageStarted(v: WebView, url: String, f: android.graphics.Bitmap?) { if (!useDocStart) v.evaluateJavascript(shim, null) }
        }
        web.loadUrl("https://appassets.androidplatform.net/assets/index.html")
        if (Build.VERSION.SDK_INT >= 33 && !has(Manifest.permission.POST_NOTIFICATIONS)) ask(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
    }

    override fun onResume() { super.onResume(); visible = true; TyreWizBle.flush() }
    override fun onPause() { visible = false; super.onPause() }
    @Deprecated("") override fun onBackPressed() { if (web.canGoBack()) web.goBack() else super.onBackPressed() }
}
