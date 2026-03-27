package com.planka.quicktest

import android.annotation.SuppressLint
import android.content.ComponentCallbacks2
import android.os.Build
import android.os.Bundle
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.planka.quicktest.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var insetsController: WindowInsetsControllerCompat
    private lateinit var resolvedUiShellConfig: ResolvedUiShellConfig
    private lateinit var diagnostics: BreakoutDiagnostics
    private var diagnosticsPanelVisible = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        resolvedUiShellConfig = UiShellConfigResolver.resolve(this)
        diagnostics = BreakoutDiagnostics(this)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        insetsController = WindowInsetsControllerCompat(window, binding.root)
        insetsController.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            diagnostics.recordInsets(
                statusVisible = insets.isVisible(WindowInsetsCompat.Type.statusBars()),
                navigationVisible = insets.isVisible(WindowInsetsCompat.Type.navigationBars()),
            )
            if (insets.isVisible(WindowInsetsCompat.Type.systemBars())) {
                binding.root.postDelayed({ hideSystemUi("system_bars_visible") }, 160L)
            }
            insets
        }
        diagnostics.onSnapshotChanged = { snapshot ->
            runOnUiThread {
                binding.diagnosticsMeta.text = getString(
                    R.string.diagnostics_meta_template,
                    snapshot.sessionId,
                    snapshot.internalPath,
                    snapshot.exportPath ?: getString(R.string.diagnostics_export_not_yet),
                )
                binding.diagnosticsLog.text = snapshot.text
                binding.diagnosticsScroll.post {
                    binding.diagnosticsScroll.fullScroll(View.FOCUS_DOWN)
                }
            }
        }
        binding.diagnosticsToggleButton.setOnClickListener {
            diagnosticsPanelVisible = !diagnosticsPanelVisible
            updateDiagnosticsPanelVisibility()
            hideSystemUi("diagnostics_toggle")
        }
        binding.diagnosticsExportButton.setOnClickListener {
            diagnostics.exportCurrentLog()
                .onSuccess { exportedPath ->
                    Toast.makeText(
                        this,
                        getString(R.string.diagnostics_export_success, exportedPath),
                        Toast.LENGTH_SHORT,
                    ).show()
                    hideSystemUi("after_export")
                }
                .onFailure { error ->
                    Toast.makeText(
                        this,
                        getString(
                            R.string.diagnostics_export_failed,
                            error.message ?: "unknown",
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    hideSystemUi("after_export_failure")
                }
        }
        updateDiagnosticsPanelVisibility()
        diagnostics.recordSessionStart(savedInstanceStateRestored = savedInstanceState != null)

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
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                hideSystemUi("webview_page_finished")
            }
        }
        webView.addJavascriptInterface(AppBridge(resolvedUiShellConfig), "AndroidApp")
        webView.loadUrl("file:///android_asset/index.html")

        hideSystemUi("on_create")
        binding.root.post { ViewCompat.requestApplyInsets(binding.root) }
    }

    override fun onStart() {
        super.onStart()
        diagnostics.recordActivityStart()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        diagnostics.recordWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi("window_focus_gained")
    }

    override fun onResume() {
        super.onResume()
        diagnostics.recordActivityResume()
        hideSystemUi("on_resume")
    }

    override fun onTopResumedActivityChanged(isTopResumedActivity: Boolean) {
        super.onTopResumedActivityChanged(isTopResumedActivity)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            diagnostics.recordTopResumedChanged(isTopResumedActivity)
            if (isTopResumedActivity) {
                hideSystemUi("top_resumed_gained")
            }
        }
    }

    override fun onPause() {
        diagnostics.recordActivityPause()
        super.onPause()
    }

    override fun onStop() {
        diagnostics.recordActivityStop()
        super.onStop()
    }

    override fun onRestart() {
        super.onRestart()
        diagnostics.recordActivityRestart()
    }

    override fun onDestroy() {
        diagnostics.recordActivityDestroy(changingConfigurations = isChangingConfigurations)
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        diagnostics.recordUserLeaveHint()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        diagnostics.recordSaveInstanceState()
        super.onSaveInstanceState(outState)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            diagnostics.recordTrimMemory(level)
        }
    }

    private fun hideSystemUi(reason: String) {
        diagnostics.recordHideSystemUiRequest(reason)
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
        binding.root.post {
            ViewCompat.requestApplyInsets(binding.root)
            diagnostics.recordHideSystemUiApplied(reason)
        }
    }

    private fun updateDiagnosticsPanelVisibility() {
        binding.diagnosticsPanel.visibility = if (diagnosticsPanelVisible) View.VISIBLE else View.GONE
        binding.diagnosticsToggleButton.text = getString(
            if (diagnosticsPanelVisible) {
                R.string.diagnostics_toggle_hide
            } else {
                R.string.diagnostics_toggle_show
            },
        )
        if (diagnosticsPanelVisible) {
            binding.diagnosticsScroll.post {
                binding.diagnosticsScroll.fullScroll(View.FOCUS_DOWN)
            }
        }
    }

    inner class AppBridge(
        private val resolvedConfig: ResolvedUiShellConfig,
    ) {
        @JavascriptInterface
        fun exitApp() {
            runOnUiThread {
                finishAndRemoveTask()
            }
        }

        @JavascriptInterface
        fun getUiShellConfig(): String = resolvedConfig.payload

        @JavascriptInterface
        fun getUiShellConfigDiagnostics(): String = resolvedConfig.diagnosticsPayload

        @JavascriptInterface
        fun getBreakoutDiagnosticsLog(): String = diagnostics.currentLogText()
    }

    override fun onBackPressed() {
        diagnostics.recordBackPressedBridge()
        binding.webView.evaluateJavascript("window.__plankaBack && window.__plankaBack();") {}
    }
}
