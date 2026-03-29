package com.planka.quicktest

import android.annotation.SuppressLint
import android.content.ComponentCallbacks2
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.WindowManager
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
import java.util.concurrent.CountDownLatch
import org.json.JSONObject

class MainActivity : AppCompatActivity() {

    companion object {
        private const val SHELL_ENTRY_URL = "file:///android_asset/index.html"
        private val immersiveRecoveryDelaysMs = longArrayOf(0L, 180L, 420L)
        private val supportedServiceActions = listOf(
            "toggleDiagnostics",
            "showDiagnostics",
            "hideDiagnostics",
            "requestFullscreenRefresh",
            "exportDiagnosticsLog",
            "reloadShell",
            "openSystemSettings",
            "closeShell",
        )
    }

    private lateinit var binding: ActivityMainBinding
    private lateinit var insetsController: WindowInsetsControllerCompat
    private lateinit var resolvedUiShellConfig: ResolvedUiShellConfig
    private lateinit var resolvedUiShellDiagnostics: JSONObject
    private lateinit var diagnostics: BreakoutDiagnostics
    private var diagnosticsPanelVisible = false
    private var webViewReady = false
    private var bridgeReady = false
    private var activityStarted = false
    private var activityResumed = false
    private var hasActivityWindowFocus = false
    private var topResumed: Boolean? = null
    private var lastShellEvent = "cold_start"
    private var lastImmersiveReason = "cold_start"
    private var immersiveRequestGeneration = 0

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        resolvedUiShellConfig = UiShellConfigResolver.resolve(this)
        resolvedUiShellDiagnostics = JSONObject(resolvedUiShellConfig.diagnosticsPayload)
        diagnostics = BreakoutDiagnostics(this)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

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
                requestImmersiveRefresh("system_bars_visible")
            }
            publishShellSnapshot("window_insets_changed")
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
                publishShellSnapshot("diagnostics_snapshot_changed")
            }
        }
        binding.diagnosticsToggleButton.setOnClickListener {
            setDiagnosticsPanelVisible(!diagnosticsPanelVisible, "diagnostics_toggle_button")
        }
        binding.diagnosticsExportButton.setOnClickListener {
            exportDiagnosticsWithFeedback()
        }
        binding.diagnosticsRecoverButton.setOnClickListener {
            requestImmersiveRefresh("diagnostics_recover_button")
        }
        binding.diagnosticsReloadButton.setOnClickListener {
            reloadShell("diagnostics_reload_button")
        }
        binding.diagnosticsCloseButton.setOnClickListener {
            finishAndRemoveTask()
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
                webViewReady = true
                bridgeReady = false
                publishShellSnapshot("webview_page_finished")
                requestImmersiveRefresh("webview_page_finished")
            }
        }
        webView.addJavascriptInterface(AppBridge(), "AndroidApp")
        loadShell()

        publishShellSnapshot("on_create")
        requestImmersiveRefresh("on_create")
        binding.root.post { ViewCompat.requestApplyInsets(binding.root) }
    }

    override fun onStart() {
        super.onStart()
        activityStarted = true
        diagnostics.recordActivityStart()
        publishShellSnapshot("activity_start")
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        hasActivityWindowFocus = hasFocus
        diagnostics.recordWindowFocusChanged(hasFocus)
        publishShellSnapshot(if (hasFocus) "window_focus_gained" else "window_focus_lost")
        if (hasFocus) requestImmersiveRefresh("window_focus_gained")
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        diagnostics.recordActivityResume()
        publishShellSnapshot("activity_resume")
        requestImmersiveRefresh("on_resume")
    }

    override fun onTopResumedActivityChanged(isTopResumedActivity: Boolean) {
        super.onTopResumedActivityChanged(isTopResumedActivity)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            topResumed = isTopResumedActivity
            diagnostics.recordTopResumedChanged(isTopResumedActivity)
            publishShellSnapshot(
                if (isTopResumedActivity) {
                    "top_resumed_gained"
                } else {
                    "top_resumed_lost"
                },
            )
            if (isTopResumedActivity) {
                requestImmersiveRefresh("top_resumed_gained")
            }
        }
    }

    override fun onPause() {
        activityResumed = false
        publishShellSnapshot("activity_pause")
        diagnostics.recordActivityPause()
        super.onPause()
    }

    override fun onStop() {
        activityStarted = false
        publishShellSnapshot("activity_stop")
        diagnostics.recordActivityStop()
        super.onStop()
    }

    override fun onRestart() {
        super.onRestart()
        diagnostics.recordActivityRestart()
        publishShellSnapshot("activity_restart")
    }

    override fun onDestroy() {
        publishShellSnapshot("activity_destroy")
        diagnostics.recordActivityDestroy(changingConfigurations = isChangingConfigurations)
        binding.webView.removeJavascriptInterface("AndroidApp")
        binding.webView.destroy()
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        diagnostics.recordUserLeaveHint()
        publishShellSnapshot("user_leave_hint")
    }

    override fun onSaveInstanceState(outState: Bundle) {
        diagnostics.recordSaveInstanceState()
        publishShellSnapshot("save_instance_state")
        super.onSaveInstanceState(outState)
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            diagnostics.recordTrimMemory(level)
            publishShellSnapshot("trim_memory_ui_hidden")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        publishShellSnapshot("new_intent")
        requestImmersiveRefresh("on_new_intent")
    }

    private fun requestImmersiveRefresh(reason: String) {
        lastImmersiveReason = reason
        val generation = ++immersiveRequestGeneration
        immersiveRecoveryDelaysMs.forEach { delayMs ->
            binding.root.postDelayed({
                if (generation != immersiveRequestGeneration || isFinishing || isDestroyed) {
                    return@postDelayed
                }
                applyImmersiveMode(reason)
            }, delayMs)
        }
        publishShellSnapshot("immersive_request:$reason")
    }

    private fun applyImmersiveMode(reason: String) {
        diagnostics.recordHideSystemUiRequest(reason)
        insetsController.hide(WindowInsetsCompat.Type.systemBars())
        binding.root.post {
            ViewCompat.requestApplyInsets(binding.root)
            diagnostics.recordHideSystemUiApplied(reason)
            publishShellSnapshot("immersive_applied:$reason")
        }
    }

    private fun loadShell() {
        webViewReady = false
        bridgeReady = false
        binding.webView.loadUrl(SHELL_ENTRY_URL)
        publishShellSnapshot("shell_load_requested")
    }

    private fun reloadShell(reason: String) {
        publishShellSnapshot("shell_reload_requested:$reason")
        requestImmersiveRefresh(reason)
        loadShell()
    }

    private fun exportDiagnosticsWithFeedback(): Result<String> = diagnostics.exportCurrentLog()
        .onSuccess { exportedPath ->
            runOnUiThread {
                Toast.makeText(
                    this,
                    getString(R.string.diagnostics_export_success, exportedPath),
                    Toast.LENGTH_SHORT,
                ).show()
                publishShellSnapshot("diagnostics_export_success")
                requestImmersiveRefresh("after_export")
            }
        }
        .onFailure { error ->
            runOnUiThread {
                Toast.makeText(
                    this,
                    getString(
                        R.string.diagnostics_export_failed,
                        error.message ?: "unknown",
                    ),
                    Toast.LENGTH_SHORT,
                ).show()
                publishShellSnapshot("diagnostics_export_failure")
                requestImmersiveRefresh("after_export_failure")
            }
        }

    private fun doOpenSystemSettingsActivity(): Result<Unit> = runCatching {
        val settingsIntent = Intent(Settings.ACTION_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(settingsIntent)
        publishShellSnapshot("system_settings_opened")
        requestImmersiveRefresh("before_system_settings")
    }.onFailure {
        publishShellSnapshot("system_settings_open_failed")
    }

    private fun openSystemSettingsActivity(): Result<Unit> {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return doOpenSystemSettingsActivity()
        }

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        runOnUiThread {
            result = doOpenSystemSettingsActivity()
            latch.countDown()
        }
        latch.await()
        return result ?: Result.failure(IllegalStateException("openSystemSettings result missing"))
    }

    private fun setDiagnosticsPanelVisible(visible: Boolean, reason: String) {
        diagnosticsPanelVisible = visible
        updateDiagnosticsPanelVisibility()
        publishShellSnapshot(
            if (visible) {
                "diagnostics_panel_shown:$reason"
            } else {
                "diagnostics_panel_hidden:$reason"
            },
        )
        requestImmersiveRefresh(reason)
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
        renderDiagnosticsShellStatus()
    }

    private fun currentShellSnapshot(): ShellRuntimeSnapshot {
        val diagnosticsSnapshot = diagnostics.currentSnapshot()
        return ShellRuntimeSnapshot(
            appVersionCode = BuildConfig.VERSION_CODE,
            appVersionName = BuildConfig.VERSION_NAME,
            configVersion = resolvedUiShellDiagnostics.optInt("configVersion"),
            requestedConfigSource = resolvedUiShellDiagnostics.optString("requestedSource", "unknown"),
            resolvedConfigSource = resolvedUiShellDiagnostics.optString("resolvedSource", "unknown"),
            diagnosticsPanelVisible = diagnosticsPanelVisible,
            webViewReady = webViewReady,
            bridgeReady = bridgeReady,
            hasWindowFocus = hasActivityWindowFocus,
            activityStarted = activityStarted,
            activityResumed = activityResumed,
            topResumed = topResumed,
            lastEvent = lastShellEvent,
            lastImmersiveReason = lastImmersiveReason,
            immersiveRecoveryDelaysMs = immersiveRecoveryDelaysMs.toList(),
            supportedActions = supportedServiceActions,
            diagnosticsSessionId = diagnosticsSnapshot.sessionId,
            diagnosticsInternalPath = diagnosticsSnapshot.internalPath,
            diagnosticsExportPath = diagnosticsSnapshot.exportPath,
        )
    }

    private fun publishShellSnapshot(event: String) {
        lastShellEvent = event
        val snapshot = currentShellSnapshot()
        renderDiagnosticsShellStatus()
        if (!webViewReady) {
            return
        }
        val payload = JSONObject.quote(snapshot.toPayload())
        binding.webView.evaluateJavascript(
            """
            (function() {
              var payload = JSON.parse($payload);
              window.__plankaShellStatus = payload;
              window.dispatchEvent(new CustomEvent("planka:shell-status", { detail: payload }));
            })();
            """.trimIndent(),
            null,
        )
    }

    private fun renderDiagnosticsShellStatus() {
        val snapshot = currentShellSnapshot()
        binding.diagnosticsShellStatus.text = getString(
            R.string.diagnostics_shell_status_template,
            snapshot.appVersionName,
            snapshot.appVersionCode,
            token(snapshot.webViewReady),
            token(snapshot.bridgeReady),
            token(snapshot.diagnosticsPanelVisible),
            token(snapshot.hasWindowFocus),
            token(snapshot.activityStarted),
            token(snapshot.activityResumed),
            optionalToken(snapshot.topResumed),
            snapshot.lastEvent,
            snapshot.lastImmersiveReason,
            snapshot.resolvedConfigSource,
        )
    }

    private fun actionResponse(
        action: String,
        ok: Boolean,
        message: String? = null,
        exportPath: String? = null,
    ): String = ShellActionResponse(
        action = action,
        ok = ok,
        snapshot = currentShellSnapshot(),
        message = message,
        exportPath = exportPath,
    ).toPayload()

    inner class AppBridge {
        @JavascriptInterface
        fun exitApp() {
            runOnUiThread {
                finishAndRemoveTask()
            }
        }

        @JavascriptInterface
        fun getUiShellConfig(): String = resolvedUiShellConfig.payload

        @JavascriptInterface
        fun getUiShellConfigDiagnostics(): String = resolvedUiShellConfig.diagnosticsPayload

        @JavascriptInterface
        fun getBreakoutDiagnosticsLog(): String = diagnostics.currentLogText()

        @JavascriptInterface
        fun getShellSnapshot(): String = currentShellSnapshot().toPayload()

        @JavascriptInterface
        fun markShellReady(): String {
            bridgeReady = true
            runOnUiThread {
                publishShellSnapshot("bridge_ready")
            }
            return actionResponse(
                action = "markShellReady",
                ok = true,
                message = "Bridge готов",
            )
        }

        @JavascriptInterface
        fun setDiagnosticsPanelVisible(visible: Boolean): String {
            diagnosticsPanelVisible = visible
            runOnUiThread {
                setDiagnosticsPanelVisible(
                    visible = visible,
                    reason = "bridge_set_diagnostics_visible",
                )
            }
            return actionResponse(
                action = "setDiagnosticsPanelVisible",
                ok = true,
                message = if (visible) "Диагностика открыта" else "Диагностика скрыта",
            )
        }

        @JavascriptInterface
        fun performServiceAction(action: String): String = when (action) {
            "toggleDiagnostics" -> {
                val nextVisibility = !diagnosticsPanelVisible
                diagnosticsPanelVisible = nextVisibility
                runOnUiThread {
                    setDiagnosticsPanelVisible(
                        visible = nextVisibility,
                        reason = "bridge_toggle_diagnostics",
                    )
                }
                actionResponse(
                    action = action,
                    ok = true,
                    message = if (nextVisibility) {
                        "Диагностика открыта"
                    } else {
                        "Диагностика скрыта"
                    },
                )
            }

            "showDiagnostics" -> setDiagnosticsPanelVisible(true)
            "hideDiagnostics" -> setDiagnosticsPanelVisible(false)
            "requestFullscreenRefresh" -> requestFullscreenRefresh("bridge_service_action")
            "exportDiagnosticsLog" -> exportDiagnosticsLog()
            "reloadShell" -> reloadShell()
            "openSystemSettings" -> openSystemSettingsViaBridge()
            "closeShell" -> {
                runOnUiThread { finishAndRemoveTask() }
                actionResponse(
                    action = action,
                    ok = true,
                    message = "Shell закрывается",
                )
            }

            else -> actionResponse(
                action = action,
                ok = false,
                message = "Неподдерживаемое service action",
            )
        }

        @JavascriptInterface
        fun requestFullscreenRefresh(reason: String?): String {
            val normalizedReason = reason?.takeIf { it.isNotBlank() } ?: "bridge_request_fullscreen"
            lastImmersiveReason = normalizedReason
            runOnUiThread {
                requestImmersiveRefresh(normalizedReason)
            }
            return actionResponse(
                action = "requestFullscreenRefresh",
                ok = true,
                message = "Запрошено восстановление fullscreen",
            )
        }

        @JavascriptInterface
        fun exportDiagnosticsLog(): String {
            val result = exportDiagnosticsWithFeedback()
            return result.fold(
                onSuccess = { exportPath ->
                    actionResponse(
                        action = "exportDiagnosticsLog",
                        ok = true,
                        message = "Лог экспортирован",
                        exportPath = exportPath,
                    )
                },
                onFailure = { error ->
                    actionResponse(
                        action = "exportDiagnosticsLog",
                        ok = false,
                        message = error.message ?: "unknown",
                    )
                },
            )
        }

        @JavascriptInterface
        fun reloadShell(): String {
            webViewReady = false
            runOnUiThread {
                reloadShell("bridge_reload_shell")
            }
            return actionResponse(
                action = "reloadShell",
                ok = true,
                message = "Локальный shell перезагружается",
            )
        }

        @JavascriptInterface
        fun openSystemSettings(): String = openSystemSettingsViaBridge()
    }

    override fun onBackPressed() {
        diagnostics.recordBackPressedBridge()
        binding.webView.evaluateJavascript("window.__plankaBack && window.__plankaBack();") {}
        requestImmersiveRefresh("back_pressed_bridge")
        publishShellSnapshot("back_pressed_bridge")
    }

    private fun token(value: Boolean): String = if (value) "1" else "0"

    private fun optionalToken(value: Boolean?): String = when (value) {
        true -> "1"
        false -> "0"
        null -> "?"
    }

    private fun openSystemSettingsViaBridge(): String {
        val result = openSystemSettingsActivity()
        return result.fold(
            onSuccess = {
                actionResponse(
                    action = "openSystemSettings",
                    ok = true,
                    message = "Открываем системные настройки Android",
                )
            },
            onFailure = { error ->
                actionResponse(
                    action = "openSystemSettings",
                    ok = false,
                    message = error.message ?: "unknown",
                )
            },
        )
    }
}
