package com.planka.quicktest

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

class BreakoutDiagnostics private constructor(
    private val logDir: File,
    private val exportTargetFactory: (String) -> ExportTarget,
    private val nowProvider: () -> Instant = { Instant.now() },
    private val sessionStartedAt: Instant = nowProvider(),
) {

    constructor(context: Context) : this(
        logDir = File(context.filesDir, "breakout-diagnostics").apply { mkdirs() },
        exportTargetFactory = { fileName ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                exportToDownloadsViaMediaStore(context, fileName)
            } else {
                exportToExternalFilesDir(context, fileName)
            }
        },
    )

    internal constructor(
        logDir: File,
        sessionStartedAt: Instant,
        nowProvider: () -> Instant = { sessionStartedAt },
        exportTargetFactory: (String) -> ExportTarget = { fileName ->
            val targetFile = File(logDir, fileName)
            targetFile.parentFile?.mkdirs()
            ExportTarget(
                path = targetFile.absolutePath,
                write = { payload ->
                    targetFile.writeText(payload, Charsets.UTF_8)
                },
            )
        },
    ) : this(
        logDir = logDir.apply { mkdirs() },
        exportTargetFactory = exportTargetFactory,
        nowProvider = nowProvider,
        sessionStartedAt = sessionStartedAt,
    )

    data class Snapshot(
        val sessionId: String,
        val internalPath: String,
        val exportPath: String?,
        val text: String,
    )

    data class ExportTarget(
        val path: String,
        val write: (String) -> Unit,
    )

    private val timestampFormatter = DateTimeFormatter.ISO_INSTANT.withZone(ZoneOffset.UTC)
    private val sessionFormatter =
        DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss-SSS", Locale.US).withZone(ZoneOffset.UTC)
    private val logFile = File(logDir, "planka-breakout-${sessionFormatter.format(sessionStartedAt)}.log")
    private val buffer = ArrayDeque<String>()
    private val maxBufferedLines = 80

    private var seq = 0
    private var exportPath: String? = null
    private var hasWindowFocus = false
    private var isStarted = false
    private var isResumed = false
    private var isTopResumed: Boolean? = null
    private var statusBarVisible: Boolean? = null
    private var navigationBarVisible: Boolean? = null
    private var leaveHintPending = false
    private var backgrounded = false
    private var restoredFromBackground = false
    private var pendingFullscreenRestore = false

    var onSnapshotChanged: ((Snapshot) -> Unit)? = null

    val sessionId: String = sessionFormatter.format(sessionStartedAt)
    val internalPath: String = logFile.absolutePath

    fun recordSessionStart(savedInstanceStateRestored: Boolean) {
        record(
            event = "SESSION_START",
            detail = if (savedInstanceStateRestored) {
                "saved_instance_state_restored"
            } else {
                "cold_start"
            },
        )
    }

    fun recordActivityStart() {
        isStarted = true
        record("ACTIVITY_START")
    }

    fun recordActivityResume() {
        val returningFromBackground = backgrounded
        val recoveringAfterLeaveHint = leaveHintPending && !returningFromBackground
        isResumed = true
        backgrounded = false
        record(
            event = "ACTIVITY_RESUME",
            detail = when {
                returningFromBackground -> "after_background"
                recoveringAfterLeaveHint -> "after_user_leave_hint"
                else -> null
            },
        )
        if (returningFromBackground || recoveringAfterLeaveHint) {
            restoredFromBackground = true
            record(
                "RETURN_TO_FOREGROUND",
                detail = if (returningFromBackground) {
                    "best_effort_after_pause_stop"
                } else {
                    "best_effort_after_pause_only"
                },
            )
        }
    }

    fun recordActivityPause() {
        isResumed = false
        record(
            event = "ACTIVITY_PAUSE",
            detail = if (leaveHintPending) "after_user_leave_hint" else null,
        )
    }

    fun recordActivityStop() {
        isStarted = false
        backgrounded = true
        record(
            event = "ACTIVITY_STOP",
            detail = if (leaveHintPending) "background_after_user_leave_hint" else "background_without_user_leave_hint",
        )
    }

    fun recordActivityRestart() {
        record("ACTIVITY_RESTART", detail = if (backgrounded) "after_background" else null)
    }

    fun recordActivityDestroy(changingConfigurations: Boolean) {
        record(
            event = "ACTIVITY_DESTROY",
            detail = if (changingConfigurations) "configuration_change" else "final_destroy",
        )
    }

    fun recordWindowFocusChanged(hasFocus: Boolean) {
        hasWindowFocus = hasFocus
        record("WINDOW_FOCUS_CHANGED", detail = if (hasFocus) "gained" else "lost")
        if (hasFocus && leaveHintPending && isResumed && !restoredFromBackground) {
            restoredFromBackground = true
            record("RETURN_TO_FOREGROUND", detail = "best_effort_after_focus_regain")
        }
    }

    fun recordTopResumedChanged(isTopResumed: Boolean) {
        this.isTopResumed = isTopResumed
        record("TOP_RESUMED_CHANGED", detail = if (isTopResumed) "gained" else "lost")
    }

    fun recordUserLeaveHint() {
        leaveHintPending = true
        record("USER_LEAVE_HINT", detail = "proxy_home_recents_launcher_or_external_surface")
    }

    fun recordTrimMemory(level: Int) {
        record(
            event = "TRIM_MEMORY",
            detail = when (level) {
                android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> "ui_hidden"
                else -> "level=$level"
            },
        )
    }

    fun recordSaveInstanceState() {
        record("SAVE_INSTANCE_STATE")
    }

    fun recordInsets(statusVisible: Boolean, navigationVisible: Boolean) {
        val statusChanged = statusBarVisible != statusVisible
        val navigationChanged = navigationBarVisible != navigationVisible
        statusBarVisible = statusVisible
        navigationBarVisible = navigationVisible
        if (statusChanged || navigationChanged) {
            val detail = "status=${booleanToken(statusVisible)},nav=${booleanToken(navigationVisible)}"
            record("SYSTEM_BARS_CHANGED", detail = detail)
        }
        maybeRecordFullscreenRestored()
    }

    fun recordHideSystemUiRequest(reason: String) {
        record("HIDE_SYSTEM_UI_REQUEST", detail = reason)
    }

    fun recordHideSystemUiApplied(reason: String) {
        record("HIDE_SYSTEM_UI_APPLIED", detail = reason)
        if (leaveHintPending && hasWindowFocus && isResumed) {
            pendingFullscreenRestore = true
            maybeRecordFullscreenRestored()
        }
    }

    fun recordBackPressedBridge() {
        record("BACK_PRESSED_BRIDGE", detail = "window.__plankaBack")
    }

    @Synchronized
    fun currentLogText(): String = snapshotText()

    fun exportCurrentLog(): Result<String> {
        val fileName = "planka-breakout-$sessionId.txt"
        val previousExportPath = exportPath
        var exportSucceeded = false
        return runCatching {
            val target = exportTargetFactory(fileName)
            target.write(snapshotText(target.path))
            exportPath = target.path
            record("EXPORT_LOG_SUCCESS", detail = target.path)
            exportSucceeded = true
            target.write(snapshotText())
            target.path
        }.onFailure { error ->
            if (!exportSucceeded) {
                exportPath = previousExportPath
            }
            record("EXPORT_LOG_FAILURE", detail = error.message ?: "unknown")
        }
    }

    @Synchronized
    fun currentSnapshot(): Snapshot = Snapshot(
        sessionId = sessionId,
        internalPath = internalPath,
        exportPath = exportPath,
        text = snapshotText(),
    )

    @Synchronized
    private fun record(event: String, detail: String? = null) {
        seq += 1
        val line = buildString {
            append(timestampFormatter.format(nowProvider()))
            append(" | seq=")
            append(String.format(Locale.US, "%04d", seq))
            append(" | session=")
            append(sessionId)
            append(" | event=")
            append(event)
            append(" | focus=")
            append(booleanToken(hasWindowFocus))
            append(" | started=")
            append(booleanToken(isStarted))
            append(" | resumed=")
            append(booleanToken(isResumed))
            append(" | topResumed=")
            append(optionalBooleanToken(isTopResumed))
            append(" | bars=status:")
            append(optionalBooleanToken(statusBarVisible))
            append(",nav:")
            append(optionalBooleanToken(navigationBarVisible))
            append(" | leaveHint=")
            append(booleanToken(leaveHintPending))
            if (!detail.isNullOrBlank()) {
                append(" | detail=")
                append(detail)
            }
        }
        appendLine(line)
    }

    @Synchronized
    private fun appendLine(line: String) {
        buffer.addLast(line)
        while (buffer.size > maxBufferedLines) {
            buffer.removeFirst()
        }
        logFile.appendText("$line\n", Charsets.UTF_8)
        publishSnapshot()
    }

    @Synchronized
    private fun snapshotText(exportPathOverride: String? = exportPath): String = buildString {
        append("# PLANKA Android breakout diagnostics\n")
        append("# session=")
        append(sessionId)
        append('\n')
        append("# internalPath=")
        append(internalPath)
        append('\n')
        exportPathOverride?.let {
            append("# exportPath=")
            append(it)
            append('\n')
        }
        buffer.forEach { line ->
            append(line)
            append('\n')
        }
    }

    @Synchronized
    private fun publishSnapshot() {
        onSnapshotChanged?.invoke(
            Snapshot(
                sessionId = sessionId,
                internalPath = internalPath,
                exportPath = exportPath,
                text = snapshotText(),
            ),
        )
    }

    @Synchronized
    private fun maybeRecordFullscreenRestored() {
        if (!pendingFullscreenRestore) {
            return
        }
        if (statusBarVisible != false || navigationBarVisible != false) {
            return
        }
        val detail = if (restoredFromBackground) {
            "after_background_return_hide_request"
        } else {
            "after_leave_hint_hide_request"
        }
        pendingFullscreenRestore = false
        restoredFromBackground = false
        leaveHintPending = false
        record("FULLSCREEN_RESTORED", detail = detail)
    }

    companion object {
        private fun exportToDownloadsViaMediaStore(
            context: Context,
            fileName: String,
        ): ExportTarget {
            val values = ContentValues()
                .apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Не удалось создать файл в Downloads через MediaStore")
            return ExportTarget(
                path = "Downloads/$fileName",
                write = { payload ->
                    context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter(Charsets.UTF_8)?.use { writer ->
                        writer.write(payload)
                    } ?: throw IOException("Не удалось открыть output stream для $uri")
                },
            )
        }

        private fun exportToExternalFilesDir(
            context: Context,
            fileName: String,
        ): ExportTarget {
            val baseDir = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
                ?: throw IOException("getExternalFilesDir вернул null")
            val targetFile = File(baseDir, fileName)
            targetFile.parentFile?.mkdirs()
            return ExportTarget(
                path = targetFile.absolutePath,
                write = { payload ->
                    targetFile.writeText(payload, Charsets.UTF_8)
                },
            )
        }
    }

    private fun booleanToken(value: Boolean): String = if (value) "1" else "0"

    private fun optionalBooleanToken(value: Boolean?): String = when (value) {
        true -> "1"
        false -> "0"
        null -> "?"
    }
}
