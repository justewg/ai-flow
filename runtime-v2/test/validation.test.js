"use strict";

const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const { createAiFlowV2StateStore } = require("../src/store");
const { createFileAdapter } = require("../src/file_adapter");
const { runRolloutValidation } = require("../src/validation");

test("runRolloutValidation proves dry-run and shadow gates without losing inspection visibility", async () => {
  const legacyStateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-validate-"));
  const storeDir = path.join(legacyStateDir, "runtime_v2", "store");
  const store = createAiFlowV2StateStore({ adapter: createFileAdapter({ storeDir }) });
  await store.init();

  const report = await runRolloutValidation(store, {
    legacyStateDir,
    storeDir,
    repo: "justewg/planka",
    taskId: "PL-104",
    issueNumber: 104,
  });

  assert.equal(report.ok, true);
  assert.equal(report.scenarios.find((item) => item.name === "dry_run_daemon_claim").reason, "rollout_dry_run");
  assert.equal(report.scenarios.find((item) => item.name === "shadow_executor_start").reason, "rollout_shadow_blocks_side_effects");
  assert.equal(report.scenarios.find((item) => item.name === "shadow_read_only_inspection").status, "applied");
  assert.equal(report.inspection.contexts.waitingCount, 1);
  assert.equal(report.inspection.contexts.waiting[0].taskId, "PL-104");
});
