"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const SCRIPT = path.join(__dirname, "../bin/provider_corpus_aggregate.js");

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
}

function telemetryRecord(taskId, ts, compareSummary = "interpretation_match") {
  return {
    ts,
    requestId: `${taskId}:${ts}`,
    taskId,
    module: "intake.interpretation",
    requestedProvider: "claude",
    effectiveProvider: "claude",
    outcome: "success",
    fallbackUsed: false,
    compareMode: "dry_run",
    primaryProvider: "local",
    shadowProvider: "claude",
    schemaValidShadow: true,
    profileMatch: true,
    targetFilesMatch: compareSummary !== "interpretation_target_files_tolerated",
    targetFilesDriftTolerated: compareSummary === "interpretation_target_files_tolerated" ? true : null,
    humanNeededMatch: true,
    compareSummary,
    tokenUsage: 10,
    latencyMs: 100,
    estimatedCost: 0.01,
  };
}

test("provider corpus aggregate can recover a stale issue set from telemetry", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "provider-corpus-aggregate-"));
  try {
    const corruptedBatch = path.join(root, "corrupted");
    const cleanBatch = path.join(root, "clean");
    fs.mkdirSync(corruptedBatch);
    fs.mkdirSync(cleanBatch);

    writeJson(path.join(corruptedBatch, "provider_corpus_summary.json"), {
      stateDir: corruptedBatch,
      module: "intake.interpretation",
      shadowProvider: "claude",
      issues: ["634", "635", "636", "637"],
      telemetry: { count: 4 },
      gateTelemetry: { count: 0 },
    });
    writeJson(path.join(corruptedBatch, "provider_corpus_gate.json"), {
      ready: false,
      blockingReasons: ["insufficient_samples:0/4"],
      module: "intake.interpretation",
      shadowProvider: "claude",
    });
    fs.writeFileSync(
      path.join(corruptedBatch, "provider_telemetry.jsonl"),
      [
        telemetryRecord("ISSUE-633", "2026-04-12T00:00:00Z"),
        telemetryRecord("ISSUE-626", "2026-04-12T00:01:00Z"),
        telemetryRecord("ISSUE-622", "2026-04-12T00:02:00Z"),
        telemetryRecord("ISSUE-641", "2026-04-12T00:03:00Z"),
        telemetryRecord("ISSUE-443", "2026-04-12T00:04:00Z", "interpretation_target_files_tolerated"),
      ]
        .map(JSON.stringify)
        .join("\n") + "\n",
    );

    writeJson(path.join(cleanBatch, "provider_corpus_summary.json"), {
      stateDir: cleanBatch,
      module: "intake.interpretation",
      shadowProvider: "claude",
      issues: ["634", "635"],
      telemetry: {
        count: 2,
        tokenUsageTotal: 20,
        latencyMsTotal: 200,
        estimatedCostTotal: 0.02,
        compareSummaryCounts: { interpretation_match: 2 },
      },
      gateTelemetry: {
        count: 2,
        tokenUsageTotal: 20,
        latencyMsTotal: 200,
        estimatedCostTotal: 0.02,
        compareSummaryCounts: { interpretation_match: 2 },
      },
    });
    writeJson(path.join(cleanBatch, "provider_corpus_gate.json"), {
      ready: true,
      blockingReasons: [],
      module: "intake.interpretation",
      shadowProvider: "claude",
    });

    const output = execFileSync(process.execPath, [
      SCRIPT,
      "--recover-issues-from-telemetry",
      "--state-dir",
      corruptedBatch,
      "--state-dir",
      cleanBatch,
    ]);
    const summary = JSON.parse(String(output));

    assert.equal(summary.ready, true);
    assert.deepEqual(summary.blockingReasons, []);
    assert.equal(summary.issueCount, 7);
    assert.deepEqual(summary.issues, ["443", "622", "626", "633", "634", "635", "641"]);
    assert.equal(summary.gateTelemetry.count, 7);
    assert.equal(summary.batches[0].recoveredFromTelemetry, true);
    assert.deepEqual(summary.batches[0].originalIssues, ["634", "635", "636", "637"]);
    assert.deepEqual(summary.batches[0].issues, ["443", "622", "626", "633", "641"]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
