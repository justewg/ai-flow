"use strict";

const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const { createAiFlowV2StateStore } = require("../src/store");
const { createFileAdapter } = require("../src/file_adapter");
const { runSingleTaskLoop } = require("../src/single_task_loop");

test("runSingleTaskLoop drives an allowlisted task from execution to reviewing", async () => {
  const legacyStateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-single-task-"));
  const storeDir = path.join(legacyStateDir, "runtime_v2", "store");
  const store = createAiFlowV2StateStore({ adapter: createFileAdapter({ storeDir }) });
  await store.init();

  const report = await runSingleTaskLoop(store, {
    legacyStateDir,
    storeDir,
    repo: "justewg/planka",
    taskId: "PL-105",
    issueNumber: 105,
    prNumber: 1055,
  });

  assert.equal(report.ok, true);
  assert.equal(report.allowedGate.status, "applied");
  assert.equal(report.deniedGate.status, "blocked");
  assert.equal(report.events.at(-1).eventType, "review.finalized");
  assert.equal(report.inspection.contexts.reviewCount, 1);
  assert.equal(report.inspection.contexts.review[0].taskId, "PL-105");
  assert.equal(report.inspection.contexts.review[0].prNumber, 1055);
  assert.equal(report.inspection.contexts.waitingCount, 0);
});
