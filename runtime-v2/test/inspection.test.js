"use strict";

const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const { createAiFlowV2StateStore } = require("../src/store");
const { createMemoryAdapter } = require("../src/memory_adapter");
const { buildInspectionSummary } = require("../src/inspection");

test("buildInspectionSummary returns operator-grade runtime summary", async () => {
  const store = createAiFlowV2StateStore({ adapter: createMemoryAdapter() });
  await store.init();

  await store.putTask({
    id: "PL-103",
    title: "Inspection task",
    repo: "justewg/planka",
    issueNumber: 103,
  });
  await store.putTaskState({
    taskId: "PL-103",
    phase: "reviewing",
    reason: "awaiting review",
    ownerMode: "auto",
    canonicalReviewPrNumber: 1030,
    canonicalWaitCommentId: "comment-103",
    budgetState: "paused_budget",
    lockState: "frozen",
    updatedAt: "2026-03-28T18:00:00.000Z",
    meta: {
      reviewFeedback: {
        commentUrl: "https://github.com/justewg/planka/issues/103#issuecomment-1",
        pendingPost: true,
        waitingSince: "2026-03-28T18:00:00.000Z",
      },
    },
  });

  const legacyStateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-inspect-"));
  fs.writeFileSync(path.join(legacyStateDir, "flow_control_mode.txt"), "SAFE\n", "utf8");
  fs.writeFileSync(path.join(legacyStateDir, "flow_control_reason.txt"), "manual hold\n", "utf8");
  fs.writeFileSync(path.join(legacyStateDir, "flow_control_changed_at.txt"), "2026-03-28T18:01:00Z\n", "utf8");
  fs.writeFileSync(
    path.join(legacyStateDir, "incident_ledger.jsonl"),
    `${JSON.stringify({ ts: "2026-03-28T18:02:00Z", type: "watchdog_supervisor", mode: "SAFE", message: "runtime paused" })}\n`,
    "utf8",
  );
  fs.writeFileSync(
    path.join(legacyStateDir, "execution_ledger.jsonl"),
    `${JSON.stringify({ ts: "2026-03-28T18:03:00Z", taskId: "PL-103", rc: "0" })}\n`,
    "utf8",
  );
  fs.writeFileSync(
    path.join(legacyStateDir, "execution_summary.json"),
    `${JSON.stringify({
      "PL-103": {
        count: 2,
        issueNumber: "103",
        lastRc: "0",
        lastFinishedAt: "2026-03-28T18:03:00Z",
        lastTerminationReason: "review handoff",
        lastProviderErrorClass: "",
      },
    }, null, 2)}\n`,
    "utf8",
  );

  const summary = await buildInspectionSummary({
    store,
    legacyStateDir,
    storeDir: path.join(legacyStateDir, "runtime_v2", "store"),
    maxRecent: 5,
  });

  assert.equal(summary.controlMode.current, "SAFE");
  assert.equal(summary.controlMode.derived, "SAFE");
  assert.equal(summary.tasks.total, 1);
  assert.equal(summary.tasks.byPhase.reviewing, 1);
  assert.equal(summary.tasks.byBudgetState.paused_budget, 1);
  assert.equal(summary.contexts.reviewCount, 1);
  assert.equal(summary.contexts.review[0].taskId, "PL-103");
  assert.equal(summary.incidents.count, 1);
  assert.equal(summary.executions.ledgerCount, 1);
  assert.equal(summary.executions.summary.taskCount, 1);
});
