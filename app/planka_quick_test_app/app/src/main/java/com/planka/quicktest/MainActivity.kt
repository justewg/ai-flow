package com.planka.quicktest

import android.annotation.SuppressLint
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.planka.quicktest.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var insetsController: WindowInsetsControllerCompat

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        insetsController = WindowInsetsControllerCompat(window, binding.root)
        insetsController.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        val webView = binding.webView
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.cacheMode = WebSettings.LOAD_DEFAULT
        webView.settings.allowFileAccess = true
        webView.settings.allowContentAccess = true
        webView.settings.useWideViewPort = true
        webView.settings.loadWithOverviewMode = true
        webView.isVerticalScrollBarEnabled = false
        webView.isHorizontalScrollBarEnabled = false
        webView.setBackgroundColor(0x0011161D)
        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {}
        webView.addJavascriptInterface(AppBridge(), "AndroidApp")
        webView.loadUrl("file:///android_asset/index.html")

        hideSystemUi()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    override fun onResume() {
        super.onResume()
        hideSystemUi()
    }

    private fun hideSystemUi() {
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
    }

    inner class AppBridge {
        @JavascriptInterface
        fun exitApp() {
            runOnUiThread {
                finishAndRemoveTask()
            }
        }
    }

    override fun onBackPressed() {
        val handled = binding.webView.evaluateJavascript("window.__plankaBack && window.__plankaBack();") {}
        // ignore normal back to keep app in-place for the test build
    }
}
