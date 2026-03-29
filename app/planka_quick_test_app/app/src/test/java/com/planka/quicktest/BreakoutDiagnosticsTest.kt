package com.planka.quicktest

import java.io.File
import java.io.IOException
import java.time.Instant
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BreakoutDiagnosticsTest {

    @Test
    fun `records breakout flow and exports stable text log`() {
        val sessionStartedAt = Instant.parse("2026-03-27T12:00:05.421Z")
        val clock = SequenceClock(sessionStartedAt)
        val logDir = createTempDirectory("planka-breakout-diagnostics-").toFile()

        try {
            val diagnostics = BreakoutDiagnostics(
                logDir = logDir,
                sessionStartedAt = sessionStartedAt,
                nowProvider = clock::next,
                exportTargetFactory = { fileName ->
                    val exportFile = File(logDir, "exports/$fileName")
                    exportFile.parentFile?.mkdirs()
                    BreakoutDiagnostics.ExportTarget(
                        path = "Downloads/$fileName",
                        write = { payload ->
                            exportFile.writeText(payload, Charsets.UTF_8)
                        },
                    )
                },
            )

            diagnostics.recordSessionStart(savedInstanceStateRestored = false)
            diagnostics.recordActivityStart()
            diagnostics.recordActivityResume()
            diagnostics.recordTopResumedChanged(true)
            diagnostics.recordWindowFocusChanged(true)
            diagnostics.recordInsets(statusVisible = false, navigationVisible = false)
            diagnostics.recordUserLeaveHint()
            diagnostics.recordActivityPause()
            diagnostics.recordTopResumedChanged(false)
            diagnostics.recordWindowFocusChanged(false)
            diagnostics.recordActivityStop()
            diagnostics.recordTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN)
            diagnostics.recordActivityRestart()
            diagnostics.recordActivityStart()
            diagnostics.recordActivityResume()
            diagnostics.recordTopResumedChanged(true)
            diagnostics.recordWindowFocusChanged(true)
            diagnostics.recordHideSystemUiRequest("on_resume")
            diagnostics.recordHideSystemUiApplied("on_resume")

            val exportPath = diagnostics.exportCurrentLog().getOrThrow()
            val snapshot = diagnostics.currentSnapshot()
            val logText = snapshot.text
            val internalFile = File(snapshot.internalPath)
            val exportedFile = File(logDir, "exports/planka-breakout-20260327-120005-421.txt")
            val exportedText = exportedFile.readText(Charsets.UTF_8)

            assertEquals("Downloads/planka-breakout-20260327-120005-421.txt", exportPath)
            assertEquals(exportPath, snapshot.exportPath)
            assertTrue(internalFile.exists())
            assertTrue(exportedFile.exists())
            assertTrue(logText.contains("# PLANKA Android breakout diagnostics"))
            assertTrue(logText.contains("# session=20260327-120005-421"))
            assertTrue(logText.contains("# exportPath=Downloads/planka-breakout-20260327-120005-421.txt"))
            assertTrue(logText.contains("event=TOP_RESUMED_CHANGED"))
            assertTrue(logText.contains("event=USER_LEAVE_HINT"))
            assertTrue(logText.contains("event=ACTIVITY_STOP"))
            assertTrue(logText.contains("detail=background_after_user_leave_hint"))
            assertTrue(logText.contains("event=TRIM_MEMORY"))
            assertTrue(logText.contains("detail=ui_hidden"))
            assertTrue(logText.contains("event=RETURN_TO_FOREGROUND"))
            assertTrue(logText.contains("detail=best_effort_after_pause_stop"))
            assertTrue(logText.contains("event=FULLSCREEN_RESTORED"))
            assertTrue(logText.contains("detail=after_background_return_hide_request"))
            assertTrue(logText.contains("event=SYSTEM_BARS_CHANGED"))
            assertTrue(logText.contains("detail=status=0,nav=0"))
            assertTrue(logText.contains("topResumed=1"))
            assertTrue(exportedText.contains("# exportPath=Downloads/planka-breakout-20260327-120005-421.txt"))
            assertTrue(exportedText.contains("event=EXPORT_LOG_SUCCESS"))
        } finally {
            logDir.deleteRecursively()
        }
    }

    @Test
    fun `keeps export path empty when export fails`() {
        val sessionStartedAt = Instant.parse("2026-03-27T12:00:05.421Z")
        val clock = SequenceClock(sessionStartedAt)
        val logDir = createTempDirectory("planka-breakout-diagnostics-").toFile()

        try {
            val diagnostics = BreakoutDiagnostics(
                logDir = logDir,
                sessionStartedAt = sessionStartedAt,
                nowProvider = clock::next,
                exportTargetFactory = { fileName ->
                    BreakoutDiagnostics.ExportTarget(
                        path = "Downloads/$fileName",
                        write = {
                            throw IOException("disk full")
                        },
                    )
                },
            )

            diagnostics.recordSessionStart(savedInstanceStateRestored = false)

            val result = diagnostics.exportCurrentLog()
            val snapshot = diagnostics.currentSnapshot()

            assertTrue(result.isFailure)
            assertNull(snapshot.exportPath)
            assertFalse(snapshot.text.contains("# exportPath=Downloads/planka-breakout-20260327-120005-421.txt"))
            assertTrue(snapshot.text.contains("event=EXPORT_LOG_FAILURE"))
            assertTrue(snapshot.text.contains("detail=disk full"))
        } finally {
            logDir.deleteRecursively()
        }
    }

    @Test
    fun `waits for hidden bars before logging fullscreen restored`() {
        val sessionStartedAt = Instant.parse("2026-03-27T12:00:05.421Z")
        val clock = SequenceClock(sessionStartedAt)
        val logDir = createTempDirectory("planka-breakout-restore-").toFile()

        try {
            val diagnostics = BreakoutDiagnostics(
                logDir = logDir,
                sessionStartedAt = sessionStartedAt,
                nowProvider = clock::next,
            )

            diagnostics.recordSessionStart(savedInstanceStateRestored = false)
            diagnostics.recordActivityStart()
            diagnostics.recordActivityResume()
            diagnostics.recordWindowFocusChanged(true)
            diagnostics.recordInsets(statusVisible = true, navigationVisible = true)
            diagnostics.recordUserLeaveHint()
            diagnostics.recordHideSystemUiRequest("focus_return")
            diagnostics.recordHideSystemUiApplied("focus_return")

            val beforeBarsHidden = diagnostics.currentLogText()

            assertFalse(beforeBarsHidden.contains("event=FULLSCREEN_RESTORED"))

            diagnostics.recordInsets(statusVisible = false, navigationVisible = false)

            val afterBarsHidden = diagnostics.currentLogText()

            assertTrue(afterBarsHidden.contains("event=FULLSCREEN_RESTORED"))
            assertTrue(afterBarsHidden.contains("detail=after_leave_hint_hide_request"))
        } finally {
            logDir.deleteRecursively()
        }
    }

    private class SequenceClock(start: Instant) {
        private var current = start

        fun next(): Instant = current.also {
            current = current.plusMillis(111)
        }
    }
}
