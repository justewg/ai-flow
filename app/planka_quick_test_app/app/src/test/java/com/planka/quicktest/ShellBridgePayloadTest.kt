package com.planka.quicktest

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellBridgePayloadTest {

    @Test
    fun `snapshot payload keeps nullable fields and lifecycle flags`() {
        val snapshot = ShellRuntimeSnapshot(
            appVersionCode = 7,
            appVersionName = "0.7.0",
            configVersion = 12,
            requestedConfigSource = "active_file",
            resolvedConfigSource = "built_in_defaults",
            diagnosticsPanelVisible = true,
            webViewReady = false,
            bridgeReady = true,
            hasWindowFocus = true,
            activityStarted = true,
            activityResumed = false,
            topResumed = null,
            lastEvent = "activity_pause",
            lastImmersiveReason = "on_resume",
            immersiveRecoveryDelaysMs = listOf(0L, 180L, 420L),
            supportedActions = listOf("toggleDiagnostics", "reloadShell"),
            diagnosticsSessionId = "20260327-120005-421",
            diagnosticsInternalPath = "/tmp/internal.log",
            diagnosticsExportPath = null,
        )

        val payload = JSONObject(snapshot.toPayload())

        assertEquals(7, payload.getInt("appVersionCode"))
        assertEquals("0.7.0", payload.getString("appVersionName"))
        assertEquals(12, payload.getInt("configVersion"))
        assertEquals("active_file", payload.getString("requestedConfigSource"))
        assertEquals("built_in_defaults", payload.getString("resolvedConfigSource"))
        assertTrue(payload.getBoolean("diagnosticsPanelVisible"))
        assertFalse(payload.getBoolean("webViewReady"))
        assertTrue(payload.getBoolean("bridgeReady"))
        assertTrue(payload.getBoolean("hasWindowFocus"))
        assertEquals("activity_pause", payload.getString("lastEvent"))
        assertEquals(3, payload.getJSONArray("immersiveRecoveryDelaysMs").length())
        assertEquals("reloadShell", payload.getJSONArray("supportedActions").getString(1))
        assertTrue(payload.isNull("topResumed"))
        assertTrue(payload.isNull("diagnosticsExportPath"))
    }

    @Test
    fun `action response nests shell snapshot and export path`() {
        val snapshot = ShellRuntimeSnapshot(
            appVersionCode = 3,
            appVersionName = "0.3.0",
            configVersion = 5,
            requestedConfigSource = "built_in_defaults",
            resolvedConfigSource = "active_file",
            diagnosticsPanelVisible = false,
            webViewReady = true,
            bridgeReady = true,
            hasWindowFocus = true,
            activityStarted = true,
            activityResumed = true,
            topResumed = true,
            lastEvent = "diagnostics_export_success",
            lastImmersiveReason = "after_export",
            immersiveRecoveryDelaysMs = listOf(0L, 180L, 420L),
            supportedActions = listOf("exportDiagnosticsLog", "reloadShell"),
            diagnosticsSessionId = "20260327-120005-421",
            diagnosticsInternalPath = "/tmp/internal.log",
            diagnosticsExportPath = "Downloads/planka-breakout.txt",
        )

        val payload = JSONObject(
            ShellActionResponse(
                action = "exportDiagnosticsLog",
                ok = true,
                snapshot = snapshot,
                message = "Лог экспортирован",
                exportPath = "Downloads/planka-breakout.txt",
            ).toPayload(),
        )

        assertEquals("exportDiagnosticsLog", payload.getString("action"))
        assertTrue(payload.getBoolean("ok"))
        assertEquals("Лог экспортирован", payload.getString("message"))
        assertEquals("Downloads/planka-breakout.txt", payload.getString("exportPath"))
        assertEquals(
            "diagnostics_export_success",
            payload.getJSONObject("snapshot").getString("lastEvent"),
        )
        assertTrue(payload.getJSONObject("snapshot").getBoolean("bridgeReady"))
    }
}
