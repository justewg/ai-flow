package com.planka.quicktest

import org.json.JSONObject
import org.json.JSONArray

data class ShellRuntimeSnapshot(
    val appVersionCode: Int,
    val appVersionName: String,
    val configVersion: Int,
    val requestedConfigSource: String,
    val resolvedConfigSource: String,
    val diagnosticsPanelVisible: Boolean,
    val webViewReady: Boolean,
    val bridgeReady: Boolean,
    val hasWindowFocus: Boolean,
    val activityStarted: Boolean,
    val activityResumed: Boolean,
    val topResumed: Boolean?,
    val lastEvent: String,
    val lastImmersiveReason: String,
    val immersiveRecoveryDelaysMs: List<Long>,
    val supportedActions: List<String>,
    val diagnosticsSessionId: String,
    val diagnosticsInternalPath: String,
    val diagnosticsExportPath: String?,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("appVersionCode", appVersionCode)
        .put("appVersionName", appVersionName)
        .put("configVersion", configVersion)
        .put("requestedConfigSource", requestedConfigSource)
        .put("resolvedConfigSource", resolvedConfigSource)
        .put("diagnosticsPanelVisible", diagnosticsPanelVisible)
        .put("webViewReady", webViewReady)
        .put("bridgeReady", bridgeReady)
        .put("hasWindowFocus", hasWindowFocus)
        .put("activityStarted", activityStarted)
        .put("activityResumed", activityResumed)
        .put("topResumed", topResumed?.let { it } ?: JSONObject.NULL)
        .put("lastEvent", lastEvent)
        .put("lastImmersiveReason", lastImmersiveReason)
        .put("immersiveRecoveryDelaysMs", JSONArray(immersiveRecoveryDelaysMs))
        .put("supportedActions", JSONArray(supportedActions))
        .put("diagnosticsSessionId", diagnosticsSessionId)
        .put("diagnosticsInternalPath", diagnosticsInternalPath)
        .put("diagnosticsExportPath", diagnosticsExportPath ?: JSONObject.NULL)

    fun toPayload(): String = toJson().toString()
}

data class ShellActionResponse(
    val action: String,
    val ok: Boolean,
    val snapshot: ShellRuntimeSnapshot,
    val message: String? = null,
    val exportPath: String? = null,
) {
    fun toPayload(): String = JSONObject()
        .put("action", action)
        .put("ok", ok)
        .put("message", message ?: JSONObject.NULL)
        .put("exportPath", exportPath ?: JSONObject.NULL)
        .put("snapshot", snapshot.toJson())
        .toString()
}
