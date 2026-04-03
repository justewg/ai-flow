"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");

const {
  createAiFlowV2StateStore,
  createFileAdapter,
  collectLegacyShadowSnapshot,
  inferTaskStateFromLegacy,
} = require("../src");

test("file adapter persists task bundle across store instances", async () => {
  const storeDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-file-"));
  const firstStore = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir }),
  });
  await firstStore.init();
  await firstStore.putTask({ id: "PL-095", title: "shadow bridge", repo: "justewg/planka" });
  await firstStore.putTaskState({ taskId: "PL-095", phase: "planned", reason: "persist", ownerMode: "human" });

  const secondStore = createAiFlowV2StateStore({
    adapter: createFileAdapter({ storeDir }),
  });
  await secondStore.init();
  const bundle = await secondStore.getTaskBundle("PL-095");
  assert.equal(bundle.task.id, "PL-095");
  assert.equal(bundle.taskState.phase, "planned");
});

test("legacy shadow projection maps waiting task into v2 waiting_human state", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-legacy-"));
  fs.writeFileSync(path.join(stateDir, "daemon_waiting_task_id.txt"), "PL-095\n");
  fs.writeFileSync(path.join(stateDir, "daemon_waiting_issue_number.txt"), "517\n");
  fs.writeFileSync(path.join(stateDir, "daemon_waiting_question_comment_id.txt"), "comment-517\n");
  fs.writeFileSync(path.join(stateDir, "flow_control_mode.txt"), "SAFE\n");
  fs.writeFileSync(path.join(stateDir, "flow_control_reason.txt"), "manual hold\n");

  const { snapshot, taskIds } = collectLegacyShadowSnapshot(stateDir);
  assert.deepEqual(taskIds, ["PL-095"]);

  const projection = inferTaskStateFromLegacy("PL-095", snapshot);
  assert.equal(projection.phase, "waiting_human");
  assert.equal(projection.canonicalWaitCommentId, "comment-517");
  assert.equal(projection.budgetState, "paused_budget");
  assert.equal(projection.lockState, "frozen");
});

test("legacy shadow projection maps active task without executor into claimed state", async () => {
  const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), "aiflow-v2-legacy-claim-"));
  fs.writeFileSync(path.join(stateDir, "daemon_active_task.txt"), "PL-096\n");
  fs.writeFileSync(path.join(stateDir, "daemon_active_item_id.txt"), "PVTI_096\n");
  fs.writeFileSync(path.join(stateDir, "daemon_active_issue_number.txt"), "518\n");
  fs.writeFileSync(path.join(stateDir, "daemon_active_claim_state.txt"), "claimed\n");
  fs.writeFileSync(path.join(stateDir, "daemon_active_claimed_at.txt"), "2026-04-02T10:00:00Z\n");

  const { snapshot, taskIds } = collectLegacyShadowSnapshot(stateDir);
  assert.deepEqual(taskIds, ["PL-096"]);

  const projection = inferTaskStateFromLegacy("PL-096", snapshot);
  assert.equal(projection.phase, "claimed");
  assert.equal(projection.reason, "legacy claimed task");
  assert.deepEqual(projection.meta, {
    claim: {
      itemId: "PVTI_096",
      issueNumber: 518,
      claimedAt: "2026-04-02T10:00:00Z",
      source: "legacy_shadow_sync_v2",
    },
  });
});
